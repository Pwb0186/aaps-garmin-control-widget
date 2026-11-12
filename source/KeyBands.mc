import Toybox.Graphics;
import Toybox.Lang;
import Toybox.Math;
import Toybox.WatchUi;

// Bands at the screen edge next to the watch keys, with what the key does
// written inside, so it is clear which key to press. Angles are degrees on the
// fr955 (0 = 3 o'clock, counter-clockwise): START upper right, BACK lower right,
// UP left middle, DOWN lower left. Sizes are for the 260 px screen, scaled to
// the screen width.
module KeyBands {
    const START_COLOR = 0x5555AA; // AAPS' purple play button, nearest on the fr955 palette
    const STOP_COLOR = Graphics.COLOR_RED;
    const BACK_COLOR = 0x555555;
    const STEP_COLOR = 0x555555;

    function start(dc as Graphics.Dc, label as String, color as Number) as Void {
        band(dc, 8, 72, color, label, 17);
    }

    function back(dc as Graphics.Dc, label as String) as Void {
        band(dc, 294, 346, BACK_COLOR, label, 17);
    }

    // UP and DOWN on the pickers: "+" and "-", a little bigger.
    function upDown(dc as Graphics.Dc) as Void {
        band(dc, 162, 198, STEP_COLOR, "+", 24);
        band(dc, 206, 242, STEP_COLOR, "-", 24);
    }

    // A band from angle a1 to a2, 28 px wide, with the label in white inside it.
    // The label follows the curve where the watch has vector fonts (CIQ 4+),
    // else it is written straight in the middle of the band. Bands in the upper
    // half read clockwise, the others counter-clockwise, so the text stays upright.
    function band(dc as Graphics.Dc, a1 as Number, a2 as Number, color as Number, label as String,
            size as Number) as Void {
        var w = dc.getWidth();
        var cx = w / 2;
        var cy = dc.getHeight() / 2;
        var s = w / 260.0;
        var mid = (118 * s).toNumber();
        dc.setColor(color, Graphics.COLOR_TRANSPARENT);
        dc.setPenWidth((28 * s).toNumber());
        dc.drawArc(cx, cy, mid, Graphics.ARC_COUNTER_CLOCKWISE, a1, a2);
        dc.setPenWidth(1);
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
        var angle = (a1 + a2) / 2;
        if ((Graphics has :getVectorFont) && (dc has :drawRadialText)) {
            var font = Graphics.getVectorFont({:face => ["RobotoCondensedBold", "RobotoRegular"],
                :size => (size * s).toNumber()});
            if (font != null) {
                dc.drawRadialText(cx, cy, font, label,
                    Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER, angle, mid,
                    angle <= 180 ? Graphics.RADIAL_TEXT_DIRECTION_CLOCKWISE : Graphics.RADIAL_TEXT_DIRECTION_COUNTER_CLOCKWISE);
                return;
            }
        }
        var rad = Math.toRadians(angle);
        dc.drawText(cx + mid * Math.cos(rad), cy - mid * Math.sin(rad), Graphics.FONT_XTINY, label,
            Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
    }
}
