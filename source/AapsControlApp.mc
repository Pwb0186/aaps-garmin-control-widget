import Toybox.Application;
import Toybox.Lang;
import Toybox.WatchUi;

class AapsControlApp extends Application.AppBase {
    function initialize() {
        AppBase.initialize();
    }

    function getInitialView() as [WatchUi.Views] or [WatchUi.Views, WatchUi.InputDelegates] {
        // Without a key AAPS would refuse every request, so the key is asked
        // for first instead of sending requests that can never succeed.
        if (Aaps.key() == null) {
            var view = new KeyView();
            return [view, new KeyDelegate(view)];
        }
        // No delegate: BACK while loading leaves the widget like on the menu.
        MainMenu.load();
        return [new StatusView(Aaps.str(Rez.Strings.Loading))];
    }

    (:glance)
    function getGlanceView() as [WatchUi.GlanceView] or [WatchUi.GlanceView, WatchUi.GlanceViewDelegate] or Null {
        return [new TtGlance()];
    }
}
