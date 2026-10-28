import Toybox.Lang;
import Toybox.WatchUi;

// Scenes as set up in AAPS: the watch lists them (/scene/list), AAPS
// describes what a scene will do (/scene/prepare), and one START press starts
// it (/scene/commit). A running scene is ended with /scene/stop, also after
// one START press, since AAPS shows nothing to prepare for that.
class SceneFlow extends ConfirmFlow {
    // The list from the last /scene/list as [id, name] pairs, kept so the menu
    // can be built again after a scene starts or ends.
    private var _items as Array<Array<String>> = [] as Array<Array<String>>;
    // Name of the scene being started; becomes MainMenu.sceneName on success.
    private var _name as String = "";

    function open() as Void {
        if (Aaps.busy) {
            return;
        }
        pushStatus(Rez.Strings.Loading);
        Aaps.send("/scene/list", {}, method(:onList));
    }

    function onList(code as Number, data as Dictionary or String or Null) as Void {
        Aaps.busy = false;
        Aaps.log("scene list " + code);
        if (Aaps.isOk(code, data)) {
            var items = (data as Dictionary)["items"];
            if (items instanceof Array) {
                _items = [] as Array<Array<String>>;
                for (var i = 0; i < items.size(); i++) {
                    var it = items[i];
                    if (it instanceof Dictionary && it["id"] instanceof String && it["name"] instanceof String) {
                        _items.add([it["id"] as String, it["name"] as String]);
                    }
                }
                // A running scene can still be ended when no scene is enabled.
                if (_items.size() == 0 && !MainMenu.sceneActive) {
                    showResult(Aaps.str(Rez.Strings.NoScenes));
                } else {
                    showMenu(buildMenu(), new SceneMenuDelegate(self));
                }
                return;
            }
        }
        showResult(Aaps.errorText(code, data, Aaps.str(Rez.Strings.UnknownAnswer)));
    }

    private function buildMenu() as WatchUi.Menu2 {
        var menu = new WatchUi.Menu2({:title => Aaps.str(Rez.Strings.Scenes)});
        if (MainMenu.sceneActive) {
            menu.addItem(new WatchUi.MenuItem(Lang.format(Aaps.str(Rez.Strings.EndScene), [runningName()]), null, :end, null));
        }
        for (var i = 0; i < _items.size(); i++) {
            // The id is the menu id, so the choice goes back to AAPS unchanged.
            menu.addItem(new WatchUi.MenuItem(_items[i][1], null, _items[i][0], null));
        }
        return menu;
    }

    function choose(item as WatchUi.MenuItem) as Void {
        if (Aaps.busy) {
            return;
        }
        var id = item.getId();
        if (id == :end) {
            var name = MainMenu.sceneName;
            var question = name != null ? Lang.format(Aaps.str(Rez.Strings.EndSceneQ), [name])
                : Lang.format(Aaps.str(Rez.Strings.EndScene), [runningName()]) + "?";
            confirmLocal([question] as Array<String>, "/scene/stop");
        } else {
            _name = item.getLabel();
            request("/scene/prepare", {"id" => id as String}, "/scene/commit");
        }
    }

    function committed(commitPath as String) as Void {
        MainMenu.sceneActive = !commitPath.equals("/scene/stop");
        MainMenu.sceneName = MainMenu.sceneActive ? _name : null;
    }

    function rebuild() as Void {
        WatchUi.switchToView(buildMenu(), new SceneMenuDelegate(self), WatchUi.SLIDE_IMMEDIATE);
    }

    // Without a usable /status the name is unknown; "scene" keeps the text readable.
    private function runningName() as String {
        var name = MainMenu.sceneName;
        return name != null ? name : Aaps.str(Rez.Strings.Scene);
    }
}

class SceneMenuDelegate extends WatchUi.Menu2InputDelegate {
    private var _flow as SceneFlow;

    function initialize(flow as SceneFlow) {
        Menu2InputDelegate.initialize();
        _flow = flow;
    }

    function onSelect(item as WatchUi.MenuItem) as Void {
        _flow.choose(item);
    }
}
