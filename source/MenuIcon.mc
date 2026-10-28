import Toybox.Graphics;
import Toybox.Lang;
import Toybox.WatchUi;

// IconMenuItem on this watch's Connect IQ calls draw() on its icon, so a plain
// BitmapResource crashes the menu ("Symbol Not Found"). This Drawable draws the
// bitmap centered in the area the menu gives it.
class MenuIcon extends WatchUi.Drawable {
    private var _bitmap as WatchUi.BitmapResource;

    function initialize(rezId as ResourceId) {
        Drawable.initialize({});
        _bitmap = WatchUi.loadResource(rezId) as WatchUi.BitmapResource;
    }

    function draw(dc as Graphics.Dc) as Void {
        dc.drawBitmap((dc.getWidth() - _bitmap.getWidth()) / 2,
            (dc.getHeight() - _bitmap.getHeight()) / 2, _bitmap);
    }
}
