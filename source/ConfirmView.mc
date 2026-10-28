import Toybox.Graphics;
import Toybox.Lang;
import Toybox.WatchUi;

// Shows the phone's own description of what will be set, so the watch never
// has to know TT values and the user confirms exactly what AAPS will do.
class ConfirmView extends WatchUi.View {
    private var _text as String;

    function initialize(lines as Array<String>) {
        View.initialize();
        var text = "";
        for (var i = 0; i < lines.size(); i++) {
            text += (i == 0 ? "" : "\n") + lines[i];
        }
        _text = text;
    }

    function onUpdate(dc as Graphics.Dc) as Void {
        var w = dc.getWidth();
        var h = dc.getHeight();
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_BLACK);
        dc.clear();

        // Box of 65% x 60% from 12% down stays inside the circle; TINY is
        // preferred and XTINY (cut with "...") only when the text is too long.
        var boxW = w * 0.65;
        var boxH = h * 0.60;
        var font = Graphics.FONT_TINY;
        var text = Graphics.fitTextToArea(_text, font, boxW, boxH, false);
        if (text == null) {
            font = Graphics.FONT_XTINY;
            text = Graphics.fitTextToArea(_text, font, boxW, boxH, true);
        }
        dc.drawText(w / 2, h * 0.12 + boxH / 2, font, text == null ? "" : text,
            Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);

        dc.setColor(Graphics.COLOR_GREEN, Graphics.COLOR_TRANSPARENT);
        dc.drawText(w / 2, h * 0.78, Graphics.FONT_XTINY, WatchUi.loadResource(Rez.Strings.ConfirmStart) as String,
            Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
        dc.setColor(Graphics.COLOR_LT_GRAY, Graphics.COLOR_TRANSPARENT);
        dc.drawText(w / 2, h * 0.87, Graphics.FONT_XTINY, WatchUi.loadResource(Rez.Strings.ConfirmBack) as String,
            Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
    }
}

// Base for screens where START acts (confirm, stop, carbs). START only counts
// when this delegate saw the key go down AND come up: a press that began on
// an earlier screen (the release after the 2 s bolus hold, a long press in a
// menu) only reaches here as a release and is ignored.
//
// onKeyPressed/onKeyReleased are used instead of onKey, because when onKey
// fires for a press (on the way down, on the way up, after a long hold) is up
// to the firmware; down and up are reported as they happen.
//
// A plain InputDelegate instead of a BehaviorDelegate: on the touch screen a
// tap is turned into onSelect, and only a deliberate press of the START key
// may act. Touch, swipe and the menu key are swallowed.
class StartKeyDelegate extends WatchUi.InputDelegate {
    private var _pressed as Boolean = false;

    function initialize() {
        InputDelegate.initialize();
    }

    // Called once per START press that both began and ended on this screen.
    function onStart() as Void {
    }

    function onKeyPressed(evt as WatchUi.KeyEvent) as Boolean {
        if (evt.getKey() == WatchUi.KEY_ENTER) {
            _pressed = true;
        }
        return true;
    }

    function onKeyReleased(evt as WatchUi.KeyEvent) as Boolean {
        if (evt.getKey() == WatchUi.KEY_ENTER && _pressed) {
            _pressed = false;
            onStart();
        }
        return true;
    }

    // START is handled above; subclasses add BACK and other keys here.
    function onKey(evt as WatchUi.KeyEvent) as Boolean {
        return true;
    }

    function onTap(evt as WatchUi.ClickEvent) as Boolean {
        return true;
    }

    function onHold(evt as WatchUi.ClickEvent) as Boolean {
        return true;
    }

    function onSwipe(evt as WatchUi.SwipeEvent) as Boolean {
        return true;
    }
}

// A TT or scene is set by one START press on this screen; BACK cancels.
class ConfirmDelegate extends StartKeyDelegate {
    private var _flow as ConfirmFlow;

    function initialize(flow as ConfirmFlow) {
        StartKeyDelegate.initialize();
        _flow = flow;
    }

    function onStart() as Void {
        _flow.commit();
    }

    function onKey(evt as WatchUi.KeyEvent) as Boolean {
        if (evt.getKey() == WatchUi.KEY_ESC) {
            _flow.close();
        }
        return true;
    }
}
