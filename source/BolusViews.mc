import Toybox.Graphics;
import Toybox.Lang;
import Toybox.System;
import Toybox.Timer;
import Toybox.WatchUi;

// Amount picker for carbs (bolus wizard, treatment) and insulin (treatment),
// through setWhole for the bolus wizard's carb time and percentage and the
// manual temp target's mg/dL and duration, and through setTenths for its mmol/L.
// Own view instead of WatchUi.Picker: the picker's look and keys differ
// between firmwares, while this only needs UP/DOWN/START.
// Insulin is kept as a whole number of hundredths of a unit, so pump steps
// never pick up float rounding and the text sent to AAPS is exact.
//
// No hold-to-repeat: on the fr955 a long UP opens the watch menu and a long
// DOWN the music controls, and a widget can not take those over. Instead
// quick presses speed up: after FAST_PRESSES presses in the same direction,
// each less than FAST_MS apart, every press moves FAST_STEPS steps, until
// the keys rest for RESET_MS.
class AmountView extends WatchUi.View {
    private const FAST_PRESSES = 5;
    private const FAST_STEPS = 5;
    private const FAST_MS = 600;
    // Longer than FAST_MS, so a short pause while watching the number does
    // not drop back to single steps.
    private const RESET_MS = 1000;

    private var _insulin as Boolean;
    private var _max as Number;
    // Grams for carbs, hundredths of a unit for insulin.
    private var _step as Number;
    // Null for the plain bolus wizard screen; the treatment screens are drawn
    // in the AAPS colours for insulin and carbs, so they are told apart at a glance.
    private var _color as Number?;
    private var _value as Number = 0;
    private var _note as String?;
    // Set by setWhole only; null keeps the carbs or insulin screen.
    private var _title as ResourceId?;
    private var _sub as String?;
    private var _unit as String?;
    private var _min as Number = 0;
    // Set by setTenths: the value is whole tenths, drawn with one decimal.
    private var _tenths as Boolean = false;
    // The current run of presses: direction, length and time of the last one.
    private var _dir as Number = 0;
    private var _count as Number = 0;
    private var _last as Number = 0;
    // Only clears the "+0,25" text when a fast run ends; the speed itself is
    // decided from the press times, so a late tick can not change a step.
    private var _fastTimer as Timer.Timer = new Timer.Timer();
    private var _fastShown as Boolean = false;

    function initialize(insulin as Boolean, max as Number, step as Number, color as Number?) {
        View.initialize();
        _insulin = insulin;
        _max = max;
        _step = step;
        _color = color;
    }

    function isInsulin() as Boolean {
        return _insulin;
    }

    // A whole number with its own title, unit and range, starting at value.
    // A min below 0 shows the sign, so carb time reads "+15" or "-10".
    function setWhole(title as ResourceId, sub as ResourceId?, unit as String, min as Number, value as Number) as Void {
        _title = title;
        _sub = sub != null ? Aaps.str(sub) : null;
        _unit = unit;
        _min = min;
        _value = value;
    }

    // A number with one decimal, kept as whole tenths like insulin is kept as
    // hundredths, so 0.1 steps never pick up float rounding.
    function setTenths(title as ResourceId, unit as String, min as Number, value as Number) as Void {
        setWhole(title, null, unit, min, value);
        _tenths = true;
    }

    function getTitle() as ResourceId? {
        return _title;
    }

    // Grams, minutes or percent; hundredths of a unit for insulin, tenths after setTenths.
    function getValue() as Number {
        return _value;
    }

    // One UP (dir 1) or DOWN (dir -1) press.
    function press(dir as Number) as Void {
        var now = System.getTimer();
        var gap = now - _last;
        var fast = _count >= FAST_PRESSES;
        if (dir == _dir && (gap < FAST_MS || (fast && gap < RESET_MS))) {
            _count++;
        } else {
            _count = 1;
        }
        _dir = dir;
        _last = now;
        fast = _count >= FAST_PRESSES;
        var value = _value + dir * (fast ? FAST_STEPS : 1) * _step;
        _value = value < _min ? _min : (value > _max ? _max : value);
        _note = null;
        _fastShown = fast;
        if (fast) {
            _fastTimer.start(method(:onFastEnd), RESET_MS, false);
        }
        WatchUi.requestUpdate();
    }

    function onFastEnd() as Void {
        _fastShown = false;
        WatchUi.requestUpdate();
    }

    // Shown in place of the hint until the amount changes.
    function setNote(text as String) as Void {
        _note = text;
        WatchUi.requestUpdate();
    }

    function onHide() as Void {
        _fastTimer.stop();
        _fastShown = false;
        _count = 0;
    }

    // Hundredths as "1.55" or "1,55", tenths as "8.0" or "8,0". Insulin always
    // has two decimals, so every pump step (0.05, 0.1, ...) reads the same way.
    private function decimalText(value as Number) as String {
        var scale = _tenths ? 10 : 100;
        return (value / scale).toString() + Aaps.str(Rez.Strings.DecimalSep) + (value % scale).format(_tenths ? "%d" : "%02d");
    }

    private function stepText(steps as Number) as String {
        var value = steps * _step;
        return (_insulin || _tenths ? decimalText(value) : value.toString()) + " " + unit();
    }

    private function unit() as String {
        var unit = _unit;
        return unit != null ? unit : (_insulin ? Aaps.str(Rez.Strings.InsulinUnit) : "g");
    }

    function onUpdate(dc as Graphics.Dc) as Void {
        var w = dc.getWidth();
        var h = dc.getHeight();
        var color = _color;
        var main = color != null ? color : Graphics.COLOR_WHITE;
        dc.setColor(main, Graphics.COLOR_BLACK);
        dc.clear();
        if (color != null) {
            dc.setPenWidth(4);
            dc.drawCircle(w / 2, h / 2, (w < h ? w : h) / 2 - 3);
            dc.setPenWidth(1);
        }
        var title = _title;
        dc.drawText(w / 2, h * 0.17, Graphics.FONT_SMALL,
            Aaps.str(title != null ? title : (_insulin ? Rez.Strings.Insulin : Rez.Strings.Carbs)),
            Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
        var sub = _sub;
        if (sub != null) {
            dc.setColor(Graphics.COLOR_LT_GRAY, Graphics.COLOR_TRANSPARENT);
            dc.drawText(w / 2, h * 0.28, Graphics.FONT_XTINY, sub,
                Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
            dc.setColor(main, Graphics.COLOR_TRANSPARENT);
        }

        var right = _insulin || _tenths ? drawDecimal(dc, w / 2, h * 0.46) : drawCarbs(dc, w / 2, h * 0.46);
        dc.drawText(right + 4, h * 0.50, Graphics.FONT_SMALL, unit(),
            Graphics.TEXT_JUSTIFY_LEFT | Graphics.TEXT_JUSTIFY_VCENTER);

        // During a fast run the hint line shows the bigger step, so the user
        // sees why the number jumps.
        var note = _note;
        var hint;
        if (note != null) {
            dc.setColor(Graphics.COLOR_YELLOW, Graphics.COLOR_TRANSPARENT);
            hint = note;
        } else if (_fastShown) {
            hint = (_dir > 0 ? "+" : "-") + stepText(FAST_STEPS);
        } else {
            dc.setColor(Graphics.COLOR_LT_GRAY, Graphics.COLOR_TRANSPARENT);
            hint = Lang.format(Aaps.str(Rez.Strings.AmountHint), [stepText(1)]);
        }
        dc.drawText(w / 2, h * 0.70, Graphics.FONT_XTINY, hint,
            Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
        dc.setColor(Graphics.COLOR_GREEN, Graphics.COLOR_TRANSPARENT);
        dc.drawText(w / 2, h * 0.80, Graphics.FONT_XTINY, Aaps.str(Rez.Strings.CarbsNext),
            Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
        dc.setColor(Graphics.COLOR_LT_GRAY, Graphics.COLOR_TRANSPARENT);
        dc.drawText(w / 2, h * 0.89, Graphics.FONT_XTINY, Aaps.str(Rez.Strings.ConfirmBack),
            Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
    }


    // The number is centred on its own and the unit hangs to the right of it,
    // so the value stays in the middle of the screen when it grows; a sign
    // hangs to the left the same way. Both return the right edge of the number.
    private function drawCarbs(dc as Graphics.Dc, x as Number, y as Float) as Number {
        var font = Graphics.FONT_NUMBER_HOT;
        var num = (_value < 0 ? -_value : _value).toString();
        var half = dc.getTextWidthInPixels(num, font) / 2;
        dc.drawText(x, y, font, num, Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
        // The number font has no "+" (nor a proper minus), so the sign is
        // drawn by hand, like the decimal comma. The digits sit close to the
        // middle of the font box, so y is their middle too.
        if (_min < 0 && _value != 0) {
            var s = dc.getTextWidthInPixels("0", font) / 4;
            var pen = s / 2 < 2 ? 2 : s / 2;
            var cx = x - half - s - 6;
            var cy = y.toNumber();
            dc.fillRectangle(cx - s, cy - pen / 2, 2 * s, pen);
            if (_value > 0) {
                dc.fillRectangle(cx - pen / 2, cy - s, pen, 2 * s);
            }
        }
        return x + half;
    }

    // The watch's number fonts have "." but no ",", so the decimal mark is
    // drawn by hand: a dot on the baseline, with a tail for the Danish comma.
    private function drawDecimal(dc as Graphics.Dc, x as Number, y as Float) as Number {
        var font = Graphics.FONT_NUMBER_HOT;
        var scale = _tenths ? 10 : 100;
        var whole = (_value / scale).toString();
        var frac = (_value % scale).format(_tenths ? "%d" : "%02d");
        var wholeW = dc.getTextWidthInPixels(whole, font);
        var fracW = dc.getTextWidthInPixels(frac, font);
        var r = dc.getTextWidthInPixels("0", font) / 8;
        if (r < 2) {
            r = 2;
        }
        var sepW = 5 * r;
        var left = x - (wholeW + sepW + fracW) / 2;
        dc.drawText(left, y, font, whole, Graphics.TEXT_JUSTIFY_LEFT | Graphics.TEXT_JUSTIFY_VCENTER);
        dc.drawText(left + wholeW + sepW, y, font, frac, Graphics.TEXT_JUSTIFY_LEFT | Graphics.TEXT_JUSTIFY_VCENTER);
        // VCENTER centres the font's full height, so the baseline is the top
        // of that box plus the ascent.
        var base = y - dc.getFontHeight(font) / 2 + Graphics.getFontAscent(font);
        var cx = left + wholeW + sepW / 2;
        var cy = base - r;
        dc.fillCircle(cx, cy, r);
        if (Aaps.str(Rez.Strings.DecimalSep).equals(",")) {
            dc.setPenWidth(r);
            dc.drawLine(cx + r * 0.6, cy, cx - r * 0.5, cy + r * 2.6);
            dc.setPenWidth(1);
        }
        return left + wholeW + sepW + fracW;
    }
}

// Keys only: touch is swallowed so a brush against the screen does not change
// the amount or move on. START here only moves on or asks AAPS; it never gives
// insulin or sets a temp target. It still needs its own press, so the release of the menu press
// that opened this screen does not skip it with 0.
//
// UP/DOWN count on the way down, so quick presses are never merged or lost
// to the firmware's own click timing; their release and onKey are ignored.
class AmountDelegate extends StartKeyDelegate {
    // The flow's own handler, so the bolus and temp target flows share the picker.
    private var _onChosen as Method(view as AmountView) as Void;
    private var _view as AmountView;

    function initialize(onChosen as Method(view as AmountView) as Void, view as AmountView) {
        StartKeyDelegate.initialize();
        _onChosen = onChosen;
        _view = view;
    }

    function onStart() as Void {
        _onChosen.invoke(_view);
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

    function onKey(evt as WatchUi.KeyEvent) as Boolean {
        if (evt.getKey() == WatchUi.KEY_ESC) {
            WatchUi.popView(WatchUi.SLIDE_RIGHT);
        }
        return true;
    }
}

// Shows AAPS' own description of the bolus and a ring along the edge that
// fills while START is held, so the user sees how far the hold has come.
class BolusConfirmView extends WatchUi.View {
    private var _text as String;
    private var _progress as Float = 0.0f;
    // A bolus is only sent while this screen is on top; anything that covers
    // it (a notification, another screen) ends the hold through onHidden.
    private var _visible as Boolean = false;
    private var _onHidden as Method() as Void;

    function initialize(lines as Array<String>, onHidden as Method() as Void) {
        View.initialize();
        var text = "";
        for (var i = 0; i < lines.size(); i++) {
            text += (i == 0 ? "" : "\n") + lines[i];
        }
        _text = text;
        _onHidden = onHidden;
    }

    function onShow() as Void {
        _visible = true;
    }

    function onHide() as Void {
        _visible = false;
        _onHidden.invoke();
    }

    function isVisible() as Boolean {
        return _visible;
    }

    function setProgress(progress as Float) as Void {
        _progress = progress;
        WatchUi.requestUpdate();
    }

    function onUpdate(dc as Graphics.Dc) as Void {
        var w = dc.getWidth();
        var h = dc.getHeight();
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_BLACK);
        dc.clear();

        // Same text box as the TT confirm screen: it stays inside the circle
        // and inside the ring, TINY preferred and XTINY cut with "..." if needed.
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
        dc.drawText(w / 2, h * 0.78, Graphics.FONT_XTINY, Aaps.str(Rez.Strings.HoldStart),
            Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
        dc.setColor(Graphics.COLOR_LT_GRAY, Graphics.COLOR_TRANSPARENT);
        dc.drawText(w / 2, h * 0.87, Graphics.FONT_XTINY, Aaps.str(Rez.Strings.ConfirmBack),
            Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);

        if (_progress > 0.0f) {
            var pen = 8;
            dc.setPenWidth(pen);
            dc.setColor(Graphics.COLOR_GREEN, Graphics.COLOR_TRANSPARENT);
            var r = (w < h ? w : h) / 2 - pen / 2 - 1;
            if (_progress >= 1.0f) {
                dc.drawCircle(w / 2, h / 2, r);
            } else {
                // Clockwise from 12 o'clock. drawArc wants 0..360, and a start
                // equal to the end would draw a full circle, so tiny arcs are skipped.
                var sweep = (360 * _progress).toNumber();
                if (sweep > 0) {
                    var end = 90 - sweep;
                    if (end < 0) {
                        end += 360;
                    }
                    dc.drawArc(w / 2, h / 2, r, Graphics.ARC_CLOCKWISE, 90, end);
                }
            }
            dc.setPenWidth(1);
        }
    }
}

// Only a 2 s hold of the START key gives a bolus. onKeyPressed/onKeyReleased
// (API 1.0.0 / 1.1.2) report the key going down and up; the flow times the
// hold. Releasing early sends nothing. The plain START click (onKey), touch,
// screen hold and the menu key are all swallowed, so nothing else can confirm.
class BolusConfirmDelegate extends WatchUi.InputDelegate {
    private var _flow as BolusFlow;

    function initialize(flow as BolusFlow) {
        InputDelegate.initialize();
        _flow = flow;
    }

    function onKeyPressed(evt as WatchUi.KeyEvent) as Boolean {
        if (evt.getKey() == WatchUi.KEY_ENTER) {
            _flow.holdStart();
        }
        return true;
    }

    function onKeyReleased(evt as WatchUi.KeyEvent) as Boolean {
        if (evt.getKey() == WatchUi.KEY_ENTER) {
            _flow.holdCancel();
        }
        return true;
    }

    function onKey(evt as WatchUi.KeyEvent) as Boolean {
        if (evt.getKey() == WatchUi.KEY_ESC) {
            _flow.close();
        }
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

// Shown right after a bolus was sent, so stopping it is one START press away
// while the pump is still delivering. Also shown when a bolus entry finds a
// bolus already running or the commit answer was unknown; then the top stays
// empty, since this watch does not know it just gave anything. After a failed
// stop the top shows why instead, and START tries again.
class StopView extends WatchUi.View {
    private var _sent as Boolean;
    private var _error as String?;

    function initialize(sent as Boolean, error as String?) {
        View.initialize();
        _sent = sent;
        _error = error;
    }

    function onUpdate(dc as Graphics.Dc) as Void {
        var w = dc.getWidth();
        var h = dc.getHeight();
        dc.setColor(Graphics.COLOR_BLACK, Graphics.COLOR_BLACK);
        dc.clear();
        var error = _error;
        if (error != null) {
            // The circle is narrow this high up; 60% x 16% stays inside it.
            dc.setColor(Graphics.COLOR_YELLOW, Graphics.COLOR_TRANSPARENT);
            var text = Graphics.fitTextToArea(error, Graphics.FONT_XTINY, w * 0.60, h * 0.16, true);
            dc.drawText(w / 2, h * 0.16, Graphics.FONT_XTINY, text == null ? "" : text,
                Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
        } else if (_sent) {
            drawCheck(dc, w / 2, (h * 0.15).toNumber(), (w * 0.14).toNumber());
        }

        dc.setColor(Graphics.COLOR_RED, Graphics.COLOR_TRANSPARENT);
        dc.fillCircle(w / 2, h / 2, w * 0.24);
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
        dc.drawText(w / 2, h / 2, Graphics.FONT_MEDIUM, "STOP",
            Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);

        dc.drawText(w / 2, h * 0.80, Graphics.FONT_TINY, Aaps.str(Rez.Strings.StopQuestion),
            Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
        dc.setColor(Graphics.COLOR_LT_GRAY, Graphics.COLOR_TRANSPARENT);
        dc.drawText(w / 2, h * 0.90, Graphics.FONT_XTINY, Aaps.str(Rez.Strings.StopStart),
            Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
    }
}

// Through StartKeyDelegate, so the release that ends the 2 s hold on the
// confirm screen can not stop the bolus it just gave.
class StopDelegate extends StartKeyDelegate {
    private var _flow as BolusFlow;

    function initialize(flow as BolusFlow) {
        StartKeyDelegate.initialize();
        _flow = flow;
    }

    function onStart() as Void {
        _flow.stopFromScreen();
    }

    function onKey(evt as WatchUi.KeyEvent) as Boolean {
        if (evt.getKey() == WatchUi.KEY_ESC) {
            _flow.close();
        }
        return true;
    }
}

// Carbs alone give no insulin, so one START press confirms them like a temp
// target; BACK cancels.
class CarbsConfirmDelegate extends StartKeyDelegate {
    private var _flow as BolusFlow;

    function initialize(flow as BolusFlow) {
        StartKeyDelegate.initialize();
        _flow = flow;
    }

    function onStart() as Void {
        _flow.confirmCarbs();
    }

    function onKey(evt as WatchUi.KeyEvent) as Boolean {
        if (evt.getKey() == WatchUi.KEY_ESC) {
            _flow.close();
        }
        return true;
    }
}
