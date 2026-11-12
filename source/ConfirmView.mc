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
        dc.setColor(Graphics.COLOR_BLACK, Graphics.COLOR_BLACK);
        dc.clear();
        drawConfirmText(dc, _text);
        KeyBands.start(dc, Aaps.str(Rez.Strings.ConfirmLabel), KeyBands.START_COLOR);
        KeyBands.back(dc, Aaps.str(Rez.Strings.CancelLabel));
    }
}

// AAPS' confirmation lines in white, in a box left of the START and BACK bands:
// 58% x 60% around a point a little left of the centre, so its right corners
// stay inside the bands' inner edge. AAPS' lines are kept whole when a font
// allows it (TINY, then XTINY): a wrapped line reads worse than a smaller one.
// Only then they are wrapped by wrapLines(), at a space and never inside "( )":
// fitTextToArea breaks inside a word and left a lone ")" of "(105%)" behind.
// fitTextToArea (cut with "...") is the last resort.
function drawConfirmText(dc as Graphics.Dc, lines as String) as Void {
    var w = dc.getWidth();
    var h = dc.getHeight();
    var boxW = (w * 0.58).toNumber();
    var boxH = (h * 0.60).toNumber();
    var font = Graphics.FONT_TINY;
    var text = wrapLines(dc, lines, font, boxW, boxH, false);
    if (text == null) {
        font = Graphics.FONT_XTINY;
        text = wrapLines(dc, lines, font, boxW, boxH, false);
    }
    if (text == null) {
        font = Graphics.FONT_TINY;
        text = wrapLines(dc, lines, font, boxW, boxH, true);
    }
    if (text == null) {
        font = Graphics.FONT_XTINY;
        text = wrapLines(dc, lines, font, boxW, boxH, true);
    }
    if (text == null) {
        text = Graphics.fitTextToArea(lines, font, boxW, boxH, true);
    }
    dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
    dc.drawText(w * 0.46, h / 2, font, text == null ? "" : text,
        Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
}

// Wraps each line at spaces so no part is wider than boxW, or null when the
// result is taller than boxH, a word is wider than boxW, or (wrap false) a line
// would need wrapping. A "(...)" group counts as one word.
function wrapLines(dc as Graphics.Dc, lines as String, font, boxW as Number, boxH as Number, wrap as Boolean) as String? {
    var out = "";
    var count = 0;
    var rest = lines as String?;
    while (rest != null) {
        var r = rest as String;
        var cut = r.find("\n");
        var line = cut == null ? r : r.substring(0, cut) as String;
        rest = cut == null ? null : r.substring(cut + 1, r.length());
        var cur = "";
        var words = line as String?;
        while (words != null) {
            var ws = words as String;
            var sp = ws.find(" ");
            var word = sp == null ? ws : ws.substring(0, sp) as String;
            words = sp == null ? null : ws.substring(sp + 1, ws.length());
            // Keep "(+10 min)" together: take words until the ")" closes it.
            if (word.find("(") != null) {
                while (word.find(")") == null && words != null) {
                    var ws2 = words as String;
                    var sp2 = ws2.find(" ");
                    word = word + " " + (sp2 == null ? ws2 : ws2.substring(0, sp2) as String);
                    words = sp2 == null ? null : ws2.substring(sp2 + 1, ws2.length());
                }
            }
            var tryLine = cur.length() == 0 ? word : cur + " " + word;
            if (cur.length() > 0 && dc.getTextWidthInPixels(tryLine, font) > boxW) {
                if (!wrap) { return null; }
                out += (count == 0 ? "" : "\n") + cur;
                count++;
                cur = word;
            } else {
                cur = tryLine;
            }
            if (dc.getTextWidthInPixels(cur, font) > boxW) { return null; }
        }
        out += (count == 0 ? "" : "\n") + cur;
        count++;
    }
    return count * Graphics.getFontHeight(font) > boxH ? null : out;
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
