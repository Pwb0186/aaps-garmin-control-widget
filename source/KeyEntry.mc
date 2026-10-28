import Toybox.Graphics;
import Toybox.Lang;
import Toybox.WatchUi;

// Entry of the AAPS control key on the watch. The key is kept in
// Application.Storage (see Aaps.key), so it is never in the source or in the
// .prg, and a built .prg can be shared. Digits only: with UP/DOWN/START a digit
// is a few presses away, while letters would need a long cycle per character.
//
// Shown when the widget opens without a stored key, and from the menu's
// "Control key" item; it always starts empty, so a new key replaces the old
// one only when it is saved.
class KeyView extends WatchUi.View {
    // Position 10 of the UP/DOWN cycle is "save", drawn as a check mark. It is
    // only in the cycle once Aaps.KEY_MIN digits are entered, so a key AAPS
    // would refuse can not be saved.
    private const DONE = 10;
    // Clear digits at the end of the entered line. Enough to check what was
    // just typed, while the rest stays hidden from someone looking on.
    private const SHOWN = 4;

    private var _digits as String = "";
    // 0-9, or DONE.
    private var _cur as Number = 0;

    function initialize() {
        View.initialize();
    }

    // One UP (dir 1) or DOWN (dir -1) press; wraps around. At the maximum
    // length only "save" is left, so the keys do nothing.
    function press(dir as Number) as Void {
        var len = _digits.length();
        if (len >= Aaps.KEY_MAX) {
            return;
        }
        var n = len >= Aaps.KEY_MIN ? DONE + 1 : DONE;
        _cur = (_cur + dir + n) % n;
        WatchUi.requestUpdate();
    }

    // START. True when "save" was chosen and the key is stored.
    function accept() as Boolean {
        if (_cur == DONE) {
            Aaps.setKey(_digits);
            return true;
        }
        _digits += _cur.toString();
        // Each digit starts at 0, so the number of presses is always the same
        // for the same digit; at the maximum only saving is left.
        _cur = _digits.length() >= Aaps.KEY_MAX ? DONE : 0;
        WatchUi.requestUpdate();
        return false;
    }

    // BACK. False when there was no digit to remove.
    function removeLast() as Boolean {
        var len = _digits.length();
        if (len == 0) {
            return false;
        }
        _digits = _digits.substring(0, len - 1) as String;
        if (_cur == DONE && len - 1 < Aaps.KEY_MIN) {
            _cur = 0;
        }
        WatchUi.requestUpdate();
        return true;
    }

    // "*" for every digit but the last SHOWN.
    private function masked() as String {
        var len = _digits.length();
        var stars = len > SHOWN ? len - SHOWN : 0;
        var text = "";
        for (var i = 0; i < stars; i++) {
            text += "*";
        }
        return text + (_digits.substring(stars, len) as String);
    }

    function onUpdate(dc as Graphics.Dc) as Void {
        var w = dc.getWidth();
        var h = dc.getHeight();
        var len = _digits.length();
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_BLACK);
        dc.clear();
        // Same layout as the amount pickers: title, the line above the number,
        // the number, and the hint lines at the bottom.
        dc.drawText(w / 2, h * 0.17, Graphics.FONT_SMALL, Aaps.str(Rez.Strings.ControlKey),
            Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
        if (len == 0) {
            dc.setColor(Graphics.COLOR_LT_GRAY, Graphics.COLOR_TRANSPARENT);
            dc.drawText(w / 2, h * 0.29, Graphics.FONT_XTINY, Aaps.str(Rez.Strings.KeyLength),
                Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
            dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
        } else {
            dc.drawText(w / 2, h * 0.29, Graphics.FONT_TINY, masked(),
                Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
        }

        if (_cur == DONE) {
            drawCheck(dc, w / 2, (h * 0.48).toNumber(), (w * 0.20).toNumber());
        } else {
            dc.drawText(w / 2, h * 0.48, Graphics.FONT_NUMBER_HOT, _cur.toString(),
                Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
        }

        var hint = len >= Aaps.KEY_MAX ? Rez.Strings.KeyMax
            : (len >= Aaps.KEY_MIN ? Rez.Strings.KeyHintSave : Rez.Strings.KeyHint);
        dc.setColor(Graphics.COLOR_LT_GRAY, Graphics.COLOR_TRANSPARENT);
        dc.drawText(w / 2, h * 0.70, Graphics.FONT_XTINY, Aaps.str(hint),
            Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
        dc.setColor(Graphics.COLOR_GREEN, Graphics.COLOR_TRANSPARENT);
        dc.drawText(w / 2, h * 0.80, Graphics.FONT_XTINY,
            Aaps.str(_cur == DONE ? Rez.Strings.KeySave : Rez.Strings.KeyNext),
            Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
        dc.setColor(Graphics.COLOR_LT_GRAY, Graphics.COLOR_TRANSPARENT);
        dc.drawText(w / 2, h * 0.89, Graphics.FONT_XTINY,
            Aaps.str(len > 0 ? Rez.Strings.KeyBack : Rez.Strings.ConfirmBack),
            Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
    }
}

// Keys only, like the pickers: touch is swallowed (StartKeyDelegate), and
// START needs its own press, so the release of the menu press or of the press
// that opened the widget does not add a digit.
class KeyDelegate extends StartKeyDelegate {
    private var _view as KeyView;

    function initialize(view as KeyView) {
        StartKeyDelegate.initialize();
        _view = view;
    }

    // A saved key is tried at once: the widget reloads /status as if it was
    // just opened.
    function onStart() as Void {
        if (_view.accept()) {
            MainMenu.reload();
        }
    }

    function onKeyPressed(evt as WatchUi.KeyEvent) as Boolean {
        var key = evt.getKey();
        if (key == WatchUi.KEY_UP) {
            _view.press(1);
            return true;
        }
        if (key == WatchUi.KEY_DOWN) {
            _view.press(-1);
            return true;
        }
        return StartKeyDelegate.onKeyPressed(evt);
    }

    // BACK removes the last digit. With none left it leaves without saving:
    // back to the menu when a key is stored, otherwise out of the widget, since
    // nothing can be sent without a key. The entry screen is the only view on
    // the stack in both cases (the menu item switches to it), so popView leaves.
    function onKey(evt as WatchUi.KeyEvent) as Boolean {
        if (evt.getKey() == WatchUi.KEY_ESC && !_view.removeLast()) {
            if (Aaps.key() != null) {
                MainMenu.reload();
            } else {
                WatchUi.popView(WatchUi.SLIDE_RIGHT);
            }
        }
        return true;
    }
}
