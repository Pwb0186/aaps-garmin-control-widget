import Toybox.Graphics;
import Toybox.Lang;
import Toybox.WatchUi;

// Shows the phone's own description of what will be set, so the watch never
// has to know TT values and the user confirms exactly what AAPS will do.
class ConfirmView extends WatchUi.View {
    private var _text as ConfirmText;

    function initialize(lines as Array<String>) {
        View.initialize();
        var text = "";
        for (var i = 0; i < lines.size(); i++) {
            text += (i == 0 ? "" : "\n") + lines[i];
        }
        _text = new ConfirmText(text);
    }

    // UP/DOWN only move the text; they never act on the confirmation.
    function scrollText(step as Number) as Void {
        _text.scroll(step);
    }

    function onUpdate(dc as Graphics.Dc) as Void {
        var w = dc.getWidth();
        var h = dc.getHeight();
        dc.setColor(Graphics.COLOR_BLACK, Graphics.COLOR_BLACK);
        dc.clear();
        _text.draw(dc);
        KeyBands.start(dc, Aaps.str(Rez.Strings.ConfirmLabel), KeyBands.START_COLOR);
        KeyBands.back(dc, Aaps.str(Rez.Strings.CancelLabel));
    }
}

// AAPS' confirmation lines in white, in a box left of the START and BACK bands:
// 58% x 60% around a point a little left of the centre, so its right corners
// stay inside the bands' inner edge. AAPS' warnings must never be cut off, so
// there is no fitTextToArea: it breaks inside words and ends with "...".
// Instead the text is always broken into whole lines by wrapLines() (at spaces,
// never inside "( )"), and what does not fit the height is reached by scrolling.
// Font order, for the least scrolling: TINY when no line needs wrapping and all
// fit the height; else XTINY (wrapped or not) when all fit; else XTINY and scroll.
// The font heights differ between the simulator and the watch, so the choice is
// made from the measures of the dc it is drawn on, once, and then kept: the
// bolus screen redraws often while the hold ring fills.
// One line per UP/DOWN press: a page jump would hide the lines that give the
// context, and the overflow is usually only a few lines.
class ConfirmText {
    private var _text as String;
    private var _lines as Array<String> = [] as Array<String>;
    private var _laidOut as Boolean = false;
    private var _font = Graphics.FONT_TINY;
    private var _lineH as Number = 1;
    // How many lines the box holds in _font.
    private var _capacity as Number = 1;
    // Index of the first shown line.
    private var _scroll as Number = 0;

    function initialize(text as String) {
        _text = text;
    }

    // Moves the window by step lines (-1 up, 1 down), kept inside the text.
    function scroll(step as Number) as Void {
        if (!_laidOut) {
            return;
        }
        var maxScroll = _lines.size() - _capacity;
        var next = _scroll + step;
        if (next > maxScroll) {
            next = maxScroll;
        }
        if (next < 0) {
            next = 0;
        }
        if (next != _scroll) {
            _scroll = next;
            WatchUi.requestUpdate();
        }
    }

    function draw(dc as Graphics.Dc) as Void {
        var w = dc.getWidth();
        var h = dc.getHeight();
        var boxW = (w * 0.58).toNumber();
        var boxH = (h * 0.60).toNumber();
        if (!_laidOut) {
            layout(dc, boxW, boxH);
        }
        var shown = _lines.size() - _scroll;
        if (shown > _capacity) {
            shown = _capacity;
        }
        var top = (h - shown * _lineH) / 2;
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
        for (var i = 0; i < shown; i++) {
            dc.drawText(w * 0.46, top + i * _lineH, _font, _lines[_scroll + i],
                Graphics.TEXT_JUSTIFY_CENTER);
        }
        // Arrows just outside the full-height block, only where there is more.
        // A scrolled text always fills the block, so its edges are fixed.
        if (_lines.size() > _capacity) {
            var s = (7 * w / 260.0).toNumber();
            if (s < 2) {
                s = 2;
            }
            var x = (w * 0.46).toNumber();
            var blockTop = (h - _capacity * _lineH) / 2;
            dc.setColor(Graphics.COLOR_LT_GRAY, Graphics.COLOR_TRANSPARENT);
            if (_scroll > 0) {
                var y = blockTop - s - 2;
                dc.fillPolygon([[x - s, y + s], [x + s, y + s], [x, y - s]] as Array<Graphics.Point2D>);
            }
            if (_scroll < _lines.size() - _capacity) {
                var y2 = blockTop + _capacity * _lineH + s + 2;
                dc.fillPolygon([[x - s, y2 - s], [x + s, y2 - s], [x, y2 + s]] as Array<Graphics.Point2D>);
            }
        }
    }

    // Picks font and lines from this dc's measures.
    private function layout(dc as Graphics.Dc, boxW as Number, boxH as Number) as Void {
        _laidOut = true;
        var whole = splitOn(_text, "\n").size();
        var tinyH = Graphics.getFontHeight(Graphics.FONT_TINY);
        var tiny = wrapLines(dc, _text, Graphics.FONT_TINY, boxW);
        if (tiny.size() == whole && tiny.size() * tinyH <= boxH) {
            _font = Graphics.FONT_TINY;
            _lines = tiny;
            _lineH = tinyH;
        } else {
            _font = Graphics.FONT_XTINY;
            _lines = wrapLines(dc, _text, Graphics.FONT_XTINY, boxW);
            _lineH = Graphics.getFontHeight(Graphics.FONT_XTINY);
        }
        _capacity = boxH / _lineH;
        if (_capacity < 1) {
            _capacity = 1;
        }
        _scroll = 0;
    }

    // Breaks each line of text at spaces so no part is wider than boxW. A
    // "(...)" group counts as one word, so "(105%)" and "(+10 min)" stay whole.
    private function wrapLines(dc as Graphics.Dc, text as String, font, boxW as Number) as Array<String> {
        var out = [] as Array<String>;
        var paragraphs = splitOn(text, "\n");
        for (var p = 0; p < paragraphs.size(); p++) {
            var words = splitOn(paragraphs[p], " ");
            var tokens = [] as Array<String>;
            var i = 0;
            while (i < words.size()) {
                var token = words[i];
                i++;
                if (token.find("(") != null) {
                    while (token.find(")") == null && i < words.size()) {
                        token = token + " " + words[i];
                        i++;
                    }
                }
                tokens.add(token);
            }
            var last = wrapTokens(dc, tokens, font, boxW, out);
            out.add(last);
        }
        return out;
    }

    // Appends the finished lines to out and returns the last, still open line.
    // A token wider than boxW (a long "( )" group, or a single long word) is
    // split at its inner spaces and, as the very last resort, between letters.
    private function wrapTokens(dc as Graphics.Dc, tokens as Array<String>, font, boxW as Number,
            out as Array<String>) as String {
        var cur = "";
        for (var i = 0; i < tokens.size(); i++) {
            var token = tokens[i];
            if (dc.getTextWidthInPixels(token, font) > boxW) {
                if (cur.length() > 0) {
                    out.add(cur);
                    cur = "";
                }
                var parts = splitOn(token, " ");
                if (parts.size() > 1) {
                    cur = wrapTokens(dc, parts, font, boxW, out);
                } else {
                    cur = hardBreak(dc, token, font, boxW, out);
                }
                continue;
            }
            var tryLine = cur.length() == 0 ? token : cur + " " + token;
            if (cur.length() > 0 && dc.getTextWidthInPixels(tryLine, font) > boxW) {
                out.add(cur);
                cur = token;
            } else {
                cur = tryLine;
            }
        }
        return cur;
    }

    // Cuts one word into pieces that fit boxW; returns the last piece.
    private function hardBreak(dc as Graphics.Dc, word as String, font, boxW as Number,
            out as Array<String>) as String {
        var piece = "";
        for (var i = 0; i < word.length(); i++) {
            var ch = word.substring(i, i + 1) as String;
            var cand = piece + ch;
            if (piece.length() > 0 && dc.getTextWidthInPixels(cand, font) > boxW) {
                out.add(piece);
                piece = ch;
            } else {
                piece = cand;
            }
        }
        return piece;
    }

    private function splitOn(s as String, sep as String) as Array<String> {
        var out = [] as Array<String>;
        var rest = s as String?;
        while (rest != null) {
            var r = rest as String;
            var cut = r.find(sep);
            if (cut == null) {
                out.add(r);
                rest = null;
            } else {
                var c = cut as Number;
                out.add(r.substring(0, c) as String);
                rest = r.substring(c + sep.length(), r.length());
            }
        }
        return out;
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
// may act. Touch, swipe and the menu key are swallowed; a swipe does not scroll
// either, so a stray touch on the screen can never change what is shown.
class StartKeyDelegate extends WatchUi.InputDelegate {
    private var _pressed as Boolean = false;

    function initialize() {
        InputDelegate.initialize();
    }

    // Called once per START press that both began and ended on this screen.
    function onStart() as Void {
    }

    // UP/DOWN (-1 / 1) for screens with scrollable text. They are handled
    // before START's state is touched, so they can never start, count or
    // cancel a START press, even while START is held.
    function onScroll(step as Number) as Void {
    }

    function onKeyPressed(evt as WatchUi.KeyEvent) as Boolean {
        var key = evt.getKey();
        if (key == WatchUi.KEY_UP) {
            onScroll(-1);
            return true;
        }
        if (key == WatchUi.KEY_DOWN) {
            onScroll(1);
            return true;
        }
        if (key == WatchUi.KEY_ENTER) {
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
    private var _view as ConfirmView;

    function initialize(flow as ConfirmFlow, view as ConfirmView) {
        StartKeyDelegate.initialize();
        _flow = flow;
        _view = view;
    }

    function onScroll(step as Number) as Void {
        _view.scrollText(step);
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
