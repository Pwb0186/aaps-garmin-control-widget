import Toybox.Lang;
import Toybox.Timer;
import Toybox.WatchUi;

// Two-step action shared by temp targets and scenes: AAPS first describes what
// it will do (a prepare request), and only one START press on the confirm
// screen sends the commit. The menu of the flow stays below; the status and
// confirm screens replace each other on top of it, so close() always returns
// to that menu.
class ConfirmFlow {
    // AAPS forgets the prepared id after about 120 s; expiring earlier on the
    // watch means a confirm is never sent for an id AAPS may have dropped.
    private const CONFIRM_MS = 60000;
    private const RESULT_MS = 3000;

    private var _commitPath as String = "";
    // Null when there is nothing to confirm, so a stray START sends nothing.
    private var _commitParams as Dictionary<Object, Object>?;
    private var _status as StatusView?;
    private var _timer as Timer.Timer = new Timer.Timer();
    // Set when AAPS did what was confirmed: the menu below may now offer the
    // wrong items, so it is built again on the way back.
    private var _rebuild as Boolean = false;
    // Views of the flow between its menu and the status/confirm screens (the
    // manual temp target pickers). They are removed too once AAPS may have
    // acted or the confirm expired, so the user is not one START away from
    // sending the same values again; a plain error goes back to the last picker.
    protected var _below as Number = 0;
    private var _toMenu as Boolean = false;

    // Asks AAPS what will happen; commitPath is sent with the id AAPS returns.
    function request(path as String, params as Dictionary<Object, Object>, commitPath as String) as Void {
        if (Aaps.busy) {
            return;
        }
        _commitPath = commitPath;
        pushStatus(Rez.Strings.Loading);
        Aaps.send(path, params, method(:onPrepare));
    }

    function onPrepare(code as Number, data as Dictionary or String or Null) as Void {
        Aaps.busy = false;
        Aaps.log("prepare " + code);
        if (Aaps.isOk(code, data)) {
            var id = (data as Dictionary)["id"];
            var lines = (data as Dictionary)["lines"];
            if (id instanceof String && lines instanceof Array) {
                // The id is passed on as the exact string received: it does not
                // fit in a 32-bit Number, so parsing it would corrupt it.
                _commitParams = {"id" => id};
                _status = null;
                WatchUi.switchToView(new ConfirmView(Aaps.toLines(lines)), new ConfirmDelegate(self), WatchUi.SLIDE_IMMEDIATE);
                startTimer(method(:onExpired), CONFIRM_MS);
                return;
            }
        }
        showResult(Aaps.errorText(code, data, Aaps.str(Rez.Strings.UnknownAnswer)));
    }

    // For actions AAPS has no prepare step for: the watch's own lines are
    // confirmed, and the screen goes straight on top of the menu.
    function confirmLocal(lines as Array<String>, commitPath as String) as Void {
        if (Aaps.busy) {
            return;
        }
        _commitPath = commitPath;
        _commitParams = {};
        WatchUi.pushView(new ConfirmView(lines), new ConfirmDelegate(self), WatchUi.SLIDE_IMMEDIATE);
        startTimer(method(:onExpired), CONFIRM_MS);
    }

    function commit() as Void {
        var params = _commitParams;
        if (Aaps.busy || params == null) {
            return;
        }
        _commitParams = null;
        _timer.stop();
        var status = new StatusView(Aaps.str(Rez.Strings.Sending));
        _status = status;
        WatchUi.switchToView(status, new StatusDelegate(method(:close)), WatchUi.SLIDE_IMMEDIATE);
        Aaps.send(_commitPath, params, method(:onCommit));
    }

    function onCommit(code as Number, data as Dictionary or String or Null) as Void {
        Aaps.busy = false;
        Aaps.log("commit " + code);
        if (Aaps.isOk(code, data)) {
            committed(_commitPath);
            _rebuild = true;
            _toMenu = true;
            // AAPS answers "OK" when there is nothing more to say; that is shown
            // as the check mark alone, any other text (e.g. "Scene ended") under it.
            var text = (data as Dictionary)["text"];
            showDone(text instanceof String && text.length() > 0 && !text.equals("OK") ? text : null);
            return;
        }
        // Only answers that prove AAPS did nothing get a plain error. Anything
        // else may hide an action that was done, so the user is sent to check
        // AAPS instead of being invited to send again.
        if (Aaps.provedNothingDone(code, data)) {
            showResult(Aaps.errorText(code, data, Aaps.str(Rez.Strings.Error)));
        } else {
            _toMenu = true;
            mayHaveActed();
            _rebuild = true;
            showUnknown(Aaps.str(Rez.Strings.UnknownCheck) + "\n(" + code + ")");
        }
    }

    // No timer: the text stays until BACK, so it is not missed while the
    // user looks away, and the menu does not invite a second try at once.
    private function showUnknown(text as String) as Void {
        _timer.stop();
        var status = _status;
        if (status != null) {
            status.setText(text);
        }
    }

    // AAPS answered ok to commitPath: the flow updates the status the menus are
    // built from, so they fit without reopening the widget.
    function committed(commitPath as String) as Void {
    }

    // AAPS' answer to the commit is unknown, so it may have acted: the flow
    // marks its TT or scene as possibly running, so the menus still offer the
    // way to end it.
    function mayHaveActed() as Void {
    }

    // Replaces the menu below (now on top) with a fresh one.
    function rebuild() as Void {
    }

    function onExpired() as Void {
        _commitParams = null;
        _toMenu = true;
        var status = new StatusView(Aaps.str(Rez.Strings.Expired));
        _status = status;
        WatchUi.switchToView(status, new StatusDelegate(method(:close)), WatchUi.SLIDE_IMMEDIATE);
        startTimer(method(:close), RESULT_MS);
    }

    // Back to the flow's menu; also the end of every result screen.
    function close() as Void {
        _timer.stop();
        _commitParams = null;
        _status = null;
        var pops = 1 + (_toMenu ? _below : 0);
        _toMenu = false;
        for (var i = 0; i < pops; i++) {
            WatchUi.popView(WatchUi.SLIDE_IMMEDIATE);
        }
        if (_rebuild) {
            _rebuild = false;
            rebuild();
        }
    }

    protected function pushStatus(text as ResourceId) as Void {
        var status = new StatusView(Aaps.str(text));
        _status = status;
        WatchUi.pushView(status, new StatusDelegate(method(:close)), WatchUi.SLIDE_IMMEDIATE);
    }

    // Replaces the loading screen with the menu the flow just built.
    protected function showMenu(menu as WatchUi.Menu2, delegate as WatchUi.Menu2InputDelegate) as Void {
        _status = null;
        WatchUi.switchToView(menu, delegate, WatchUi.SLIDE_IMMEDIATE);
    }

    protected function showResult(text as String) as Void {
        var status = _status;
        if (status != null) {
            status.setText(text);
        }
        startTimer(method(:close), RESULT_MS);
    }

    protected function showDone(text as String?) as Void {
        var status = _status;
        if (status != null) {
            status.setDone(text);
        }
        startTimer(method(:close), RESULT_MS);
    }

    private function startTimer(callback as Method() as Void, ms as Number) as Void {
        _timer.stop();
        _timer.start(callback, ms, false);
    }
}
