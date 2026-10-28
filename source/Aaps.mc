import Toybox.Application;
import Toybox.Communications;
import Toybox.Lang;
import Toybox.System;
import Toybox.WatchUi;

// Shared by the temp target and bolus flows: one place that talks to the AAPS
// HTTP server, so only one request can be out at a time across the whole widget.
// The one exception is /bolus/stop, which must never wait (see sendStop).
module Aaps {
    const URL = "http://127.0.0.1:28891";

    // The control key is typed in on the watch (KeyView) and kept in Storage,
    // so it is never built into the .prg. AAPS refuses keys shorter than 8
    // characters; 16 digits are plenty and still fit on one line when typed.
    const KEY_STORAGE = "ControlKey";
    const KEY_MIN = 8;
    const KEY_MAX = 16;

    // True while a request is out. The callback clears it before acting on the
    // answer, so a new request is never sent before the previous one is resolved.
    var busy as Boolean = false;
    // True while a /bolus/stop is out. Kept apart from busy, so a stop is sent
    // even while a /status poll is out; onStop clears it.
    var stopping as Boolean = false;

    function send(path as String, params as Dictionary<Object, Object>, callback as Method) as Void {
        busy = true;
        request(path, params, callback);
    }

    // Sent at once, even when another request is out: Connect IQ queues it,
    // and a stop that waited could let more insulin through. Sending it twice
    // is harmless, so it does not need the one-at-a-time rule.
    function sendStop(callback as Method) as Void {
        stopping = true;
        request("/bolus/stop", {}, callback);
    }

    // True while any request is out; screens use it to swallow BACK, since
    // leaving would hide the answer.
    function waiting() as Boolean {
        return busy || stopping;
    }

    // The stored control key, or null when none (or a too short one) is stored;
    // then the widget opens on key entry instead of sending anything.
    function key() as String? {
        var k = Application.Storage.getValue(KEY_STORAGE);
        if (k instanceof String && k.length() >= KEY_MIN) {
            return k;
        }
        return null;
    }

    function setKey(k as String) as Void {
        Application.Storage.setValue(KEY_STORAGE, k);
    }

    // The key is added here, so callers never handle it and it is never logged.
    function request(path as String, params as Dictionary<Object, Object>, callback as Method) as Void {
        log("GET " + path);
        var k = key();
        if (k != null) {
            params["key"] = k;
        }
        Communications.makeWebRequest(URL + path, params,
            {:method => Communications.HTTP_REQUEST_METHOD_GET,
             :responseType => Communications.HTTP_RESPONSE_CONTENT_TYPE_JSON},
            callback);
    }

    // True only for answers to a commit that prove AAPS did not act on it:
    // AAPS refused the key (401, 403, 429), or it answered ok:false without
    // saying it is unsure ("unknown":true). Everything else, also a timeout or
    // no phone, may hide an action and is treated as unknown by the caller.
    function provedNothingDone(code as Number, data as Dictionary or String or Null) as Boolean {
        if (code == 401 || code == 403 || code == 429) {
            return true;
        }
        return code == 200 && data instanceof Dictionary && data["ok"] == false && data["unknown"] != true;
    }

    // JSON numbers arrive as Number, Long, Float or Double depending on their
    // size and whether they have decimals.
    function isNumeric(x as Object?) as Boolean {
        return x instanceof Number || x instanceof Long || x instanceof Float || x instanceof Double;
    }

    function isOk(code as Number, data as Dictionary or String or Null) as Boolean {
        return code == 200 && data instanceof Dictionary && data["ok"] == true;
    }

    function errorText(code as Number, data as Dictionary or String or Null, unknown as String) as String {
        if (code == 200) {
            if (data instanceof Dictionary && data["error"] instanceof String) {
                return data["error"] as String;
            }
            return unknown;
        }
        if (code == 401) {
            return str(Rez.Strings.WrongKey);
        }
        if (code == 403) {
            return str(Rez.Strings.NoKeyInAaps);
        }
        if (code == 429) {
            return str(Rez.Strings.Locked);
        }
        if (code == Communications.BLE_CONNECTION_UNAVAILABLE) {
            return str(Rez.Strings.NoPhone);
        }
        // UNKNOWN_ERROR and NETWORK_REQUEST_TIMED_OUT: the phone was reached but
        // nothing answered on the port, i.e. the AAPS Garmin plugin is off.
        if (code == 0 || code == Communications.NETWORK_REQUEST_TIMED_OUT) {
            return str(Rez.Strings.NoAnswer);
        }
        return str(Rez.Strings.Error) + " " + code;
    }

    // AAPS sends lines as JSON values; they are shown verbatim as text.
    function toLines(lines as Array) as Array<String> {
        var text = [] as Array<String>;
        for (var i = 0; i < lines.size(); i++) {
            text.add("" + lines[i]);
        }
        return text;
    }

    // Own texts come from string resources so they follow the watch language;
    // texts sent by AAPS (lines, text, error) are shown as received.
    function str(id as ResourceId) as String {
        return WatchUi.loadResource(id) as String;
    }

    // Debug builds only (monkeyc without -r); the key is never logged.
    (:debug)
    function log(msg as String) as Void {
        System.println(msg);
    }

    (:release)
    function log(msg as String) as Void {
    }
}
