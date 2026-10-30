import Toybox.Lang;
import Toybox.WatchUi;

// Top level of the widget. It stays at the bottom of the view stack, so BACK
// from every sub flow ends here and BACK here leaves the widget.
module MainMenu {
    // From /status when the widget opened, and set by the flows when AAPS
    // answers ok to a TT or scene, so the sub menus offer Cancel/End correctly
    // without reopening the widget.
    var ttActive as Boolean = true;
    var sceneActive as Boolean = true;
    var sceneName as String? = null;
    // The glucose unit set in AAPS, so the manual temp target is chosen in the
    // numbers the user knows; mmol/L when /status does not say.
    var mgdl as Boolean = false;

    // The widget opens on a loading screen; AAPS' /status answer decides which
    // items are worth showing, and then the menu replaces that screen.
    function load() as Void {
        Aaps.send("/status", {}, new Lang.Method(MainMenu, :onStatus));
    }

    // From key entry: back to the loading screen, as when the widget opens, so
    // a new key is tried on /status at once. Key entry replaced the menu (see
    // MainMenuDelegate), so the new menu is again the only view and BACK on it
    // still leaves the widget.
    function reload() as Void {
        WatchUi.switchToView(new StatusView(Aaps.str(Rez.Strings.Loading)), null, WatchUi.SLIDE_IMMEDIATE);
        load();
    }

    // Without a usable answer every item is shown, so Stop bolus, Cancel TT and
    // End scene can always be reached; AAPS still rejects what does not apply.
    function onStatus(code as Number, data as Dictionary or String or Null) as Void {
        Aaps.busy = false;
        Aaps.log("status " + code);
        var showQw = true;
        var showScenes = true;
        var showTreatment = true;
        if (Aaps.isOk(code, data)) {
            var d = data as Dictionary;
            var qwCount = d["qwCount"];
            var tt = d["ttActive"];
            if (qwCount instanceof Number && tt instanceof Boolean) {
                showQw = qwCount > 0;
                ttActive = tt;
            }
            var sceneCount = d["sceneCount"];
            var scene = d["sceneActive"];
            if (sceneCount instanceof Number && scene instanceof Boolean) {
                sceneActive = scene;
                showScenes = sceneCount > 0 || scene;
                var name = d["sceneName"];
                sceneName = scene && name instanceof String ? name : null;
            }
            var units = d["units"];
            mgdl = units instanceof String && units.equals("mgdl");
            var bolusOn = d["bolusEnabled"];
            var carbsOn = d["carbsEnabled"];
            if (bolusOn instanceof Boolean && carbsOn instanceof Boolean) {
                showTreatment = bolusOn || carbsOn;
            }
        }
        WatchUi.switchToView(build(showQw, showScenes, showTreatment), new MainMenuDelegate(), WatchUi.SLIDE_IMMEDIATE);
    }

    // Stop bolus is always shown and is the last command, so it is found in the
    // same place. Control key is below it: setup, not a command.
    function build(showQw as Boolean, showScenes as Boolean, showTreatment as Boolean) as WatchUi.Menu2 {
        var menu = new WatchUi.Menu2({:title => "AAPS"});
        menu.addItem(item(Rez.Strings.TempTarget, :tt, Rez.Drawables.MenuTt));
        if (showScenes) {
            menu.addItem(item(Rez.Strings.Scenes, :scenes, Rez.Drawables.MenuScene));
        }
        if (showQw) {
            menu.addItem(item(Rez.Strings.QuickWizard, :qw, Rez.Drawables.MenuQw));
        }
        menu.addItem(item(Rez.Strings.BolusWizard, :wizard, Rez.Drawables.MenuWizard));
        if (showTreatment) {
            menu.addItem(item(Rez.Strings.Treatment, :treatment, Rez.Drawables.MenuTreatment));
        }
        menu.addItem(item(Rez.Strings.StopBolus, :stop, Rez.Drawables.MenuStop));
        // Grey icon, unlike the coloured commands, so the setup item stays apart.
        menu.addItem(item(Rez.Strings.ControlKey, :key, Rez.Drawables.MenuKey));
        return menu;
    }

    function item(label as ResourceId, id as Symbol, icon as ResourceId) as WatchUi.IconMenuItem {
        return new WatchUi.IconMenuItem(Aaps.str(label), null, id, new MenuIcon(icon), null);
    }
}

class MainMenuDelegate extends WatchUi.Menu2InputDelegate {
    // One flow object per kind for the life of the widget; each holds its own
    // timers, and Aaps.busy keeps their requests from overlapping.
    private var _tt as TtFlow = new TtFlow();
    private var _scene as SceneFlow = new SceneFlow();
    private var _bolus as BolusFlow = new BolusFlow();

    function initialize() {
        Menu2InputDelegate.initialize();
    }

    function onSelect(item as WatchUi.MenuItem) as Void {
        var id = item.getId();
        // Stop never waits: a late /status poll from a stop screen that was
        // just left may still be out, and its answer is ignored.
        if (id == :stop) {
            _bolus.stopBolus();
            return;
        }
        // A sub flow is never started while a request is out, so an answer can
        // not land in a screen that belongs to another flow.
        if (Aaps.waiting()) {
            return;
        }
        if (id == :tt) {
            WatchUi.pushView(_tt.buildMenu(MainMenu.ttActive), new TtMenuDelegate(_tt), WatchUi.SLIDE_LEFT);
        } else if (id == :scenes) {
            _scene.open();
        } else if (id == :qw) {
            _bolus.openQuickWizard();
        } else if (id == :wizard) {
            _bolus.openWizard();
        } else if (id == :treatment) {
            _bolus.openTreatment();
        } else if (id == :key) {
            // Replaces the menu instead of covering it, so leaving key entry
            // can reload the menu with /status without stacking a second one.
            var view = new KeyView();
            WatchUi.switchToView(view, new KeyDelegate(view), WatchUi.SLIDE_LEFT);
        }
    }
}
