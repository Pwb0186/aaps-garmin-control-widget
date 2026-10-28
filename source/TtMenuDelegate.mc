import Toybox.Lang;
import Toybox.WatchUi;

class TtMenuDelegate extends WatchUi.Menu2InputDelegate {
    private var _flow as TtFlow;

    function initialize(flow as TtFlow) {
        Menu2InputDelegate.initialize();
        _flow = flow;
    }

    // The item id is the preset name AAPS expects, so no mapping is needed;
    // only Manual asks for its values first.
    function onSelect(item as WatchUi.MenuItem) as Void {
        var id = item.getId() as String;
        if (id.equals("manual")) {
            _flow.openManual();
        } else {
            _flow.prepare(id);
        }
    }
}
