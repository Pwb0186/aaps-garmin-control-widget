import Toybox.Graphics;
import Toybox.Lang;
import Toybox.WatchUi;

// Green check mark of two round-capped strokes, centred on (cx, cy) and size
// pixels wide. Drawn instead of a font glyph, because the watch fonts have no
// check mark.
function drawCheck(dc as Graphics.Dc, cx as Number, cy as Number, size as Number) as Void {
    var pen = size / 5;
    var ax = cx - size / 2;
    var bx = cx - size / 6;
    var by = cy + size / 3;
    var cx2 = cx + size / 2;
    var cy2 = cy - size / 3;
    dc.setColor(Graphics.COLOR_GREEN, Graphics.COLOR_TRANSPARENT);
    dc.setPenWidth(pen);
    dc.drawLine(ax, cy, bx, by);
    dc.drawLine(bx, by, cx2, cy2);
    dc.setPenWidth(1);
    // Thick lines end square; the circles round the ends and fill the corner.
    dc.fillCircle(ax, cy, pen / 2);
    dc.fillCircle(bx, by, pen / 2);
    dc.fillCircle(cx2, cy2, pen / 2);
}

// One centred message: progress ("Loading..."), result or error. A success
// is a big check mark alone, or a small one above AAPS' text when the text
// says more than "it worked".
class StatusView extends WatchUi.View {
    private var _text as String;
    private var _done as Boolean = false;

    function initialize(text as String) {
        View.initialize();
        _text = text;
    }

    function setText(text as String) as Void {
        _text = text;
        _done = false;
        WatchUi.requestUpdate();
    }

    // text is null when there is nothing to say beyond success.
    function setDone(text as String?) as Void {
        _text = text == null ? "" : text;
        _done = true;
        WatchUi.requestUpdate();
    }

    function onUpdate(dc as Graphics.Dc) as Void {
        var w = dc.getWidth();
        var h = dc.getHeight();
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_BLACK);
        dc.clear();
        if (_done && _text.length() == 0) {
            drawCheck(dc, w / 2, h / 2, (w * 0.4).toNumber());
            return;
        }
        // A box of 77% x 58% stays inside the round screen, so wrapped text is
        // never clipped. Under a check mark the box is lower and shorter.
        var y = h / 2;
        var boxH = h * 0.58;
        if (_done) {
            drawCheck(dc, w / 2, (h * 0.30).toNumber(), (w * 0.14).toNumber());
            dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
            y = h * 0.58;
            boxH = h * 0.40;
        }
        var text = Graphics.fitTextToArea(_text, Graphics.FONT_SMALL, w * 0.77, boxH, true);
        dc.drawText(w / 2, y, Graphics.FONT_SMALL, text == null ? _text : text,
            Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
    }
}

// Takes the close callback of whichever flow opened the screen, so the temp
// target and bolus flows share it. Only the BACK key closes it: a
// BehaviorDelegate also takes a swipe right on touch models as BACK, which
// could dismiss an unknown commit result before it is read.
class StatusDelegate extends WatchUi.InputDelegate {
    private var _close as Method() as Void;

    function initialize(close as Method() as Void) {
        InputDelegate.initialize();
        _close = close;
    }

    // While a request is out, BACK is swallowed: leaving now would hide the
    // answer, and for a commit that answer is the only proof of what AAPS did.
    function onKey(evt as WatchUi.KeyEvent) as Boolean {
        if (evt.getKey() == WatchUi.KEY_ESC && !Aaps.waiting()) {
            _close.invoke();
        }
        return true;
    }

    function onSwipe(evt as WatchUi.SwipeEvent) as Boolean {
        return true;
    }
}
