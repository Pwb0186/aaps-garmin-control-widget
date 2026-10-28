import Toybox.Graphics;
import Toybox.Lang;
import Toybox.WatchUi;

// A widget is only offered in the glance loop on this watch when it has a
// glance view. The watch shows the launcher icon left of it, so the view only
// shows the name. Opening it starts the menu.
(:glance)
class TtGlance extends WatchUi.GlanceView {
    function initialize() {
        GlanceView.initialize();
    }

    function onUpdate(dc as Graphics.Dc) as Void {
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
        dc.drawText(0, dc.getHeight() / 2, Graphics.FONT_GLANCE, "AAPS",
            Graphics.TEXT_JUSTIFY_LEFT | Graphics.TEXT_JUSTIFY_VCENTER);
    }
}
