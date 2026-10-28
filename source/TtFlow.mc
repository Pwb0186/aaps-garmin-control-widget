import Toybox.Lang;
import Toybox.WatchUi;

// Temp target: /tt/prepare lets AAPS describe what it will do, /tt/commit
// (only after START on the confirm screen) makes it happen. Manual first asks
// for target and duration on the watch; AAPS checks them against its own
// limits and describes the result like any preset.
class TtFlow extends ConfirmFlow {
    // AAPS' limits for a manual temp target; it refuses anything outside them.
    // mmol/L is kept as whole tenths, so 0.1 steps stay exact.
    private const MMOL_MIN = 40;
    private const MMOL_MAX = 100;
    private const MMOL_START = 70;
    private const MGDL_MIN = 72;
    private const MGDL_MAX = 180;
    private const MGDL_START = 126;
    private const DURATION_STEP = 15;
    private const DURATION_MAX = 720;
    private const DURATION_START = 60;

    private var _preset as String = "";
    // Manual: the target from the first screen, in tenths of mmol/L or in mg/dL.
    private var _target as Number = 0;

    function buildMenu(showCancel as Boolean) as WatchUi.Menu2 {
        var menu = new WatchUi.Menu2({:title => Aaps.str(Rez.Strings.TempTarget)});
        // Same icons as the AAPS temp target buttons, so the choice is recognised at a glance.
        menu.addItem(iconItem(Rez.Strings.Activity, "activity", Rez.Drawables.TtActivity));
        menu.addItem(iconItem(Rez.Strings.EatingSoon, "eating", Rez.Drawables.TtEating));
        menu.addItem(iconItem(Rez.Strings.Hypo, "hypo", Rez.Drawables.TtHypo));
        menu.addItem(iconItem(Rez.Strings.ManualTt, "manual", Rez.Drawables.TtManual));
        if (showCancel) {
            menu.addItem(iconItem(Rez.Strings.CancelTt, "cancel", Rez.Drawables.TtCancel));
        }
        return menu;
    }

    private function iconItem(label as ResourceId, id as String, icon as ResourceId) as WatchUi.IconMenuItem {
        return new WatchUi.IconMenuItem(Aaps.str(label), null, id, new MenuIcon(icon), null);
    }

    function prepare(preset as String) as Void {
        if (Aaps.busy) {
            return;
        }
        _preset = preset;
        _below = 0;
        request("/tt/prepare", {"preset" => preset}, "/tt/commit");
    }

    // The target is picked in AAPS' own unit, so the numbers are the ones the
    // user knows from AAPS.
    function openManual() as Void {
        if (Aaps.busy) {
            return;
        }
        var view;
        if (MainMenu.mgdl) {
            view = new AmountView(false, MGDL_MAX, 1, null);
            view.setWhole(Rez.Strings.Target, null, "mg/dL", MGDL_MIN, MGDL_START);
        } else {
            view = new AmountView(false, MMOL_MAX, 1, null);
            view.setTenths(Rez.Strings.Target, "mmol/L", MMOL_MIN, MMOL_START);
        }
        showAmount(view);
    }

    // START on the target or the duration screen.
    function amountChosen(view as AmountView) as Void {
        if (Aaps.busy) {
            return;
        }
        if (view.getTitle() == Rez.Strings.Target) {
            _target = view.getValue();
            var duration = new AmountView(false, DURATION_MAX, DURATION_STEP, null);
            duration.setWhole(Rez.Strings.Duration, null, "min", DURATION_STEP, DURATION_START);
            showAmount(duration);
            return;
        }
        _preset = "manual";
        _below = 2;
        // "." and one decimal for mmol/L whatever the watch language, a whole
        // number for mg/dL, as AAPS expects.
        var target = MainMenu.mgdl ? _target.toString()
            : (_target / 10).toString() + "." + (_target % 10).toString();
        request("/tt/prepare", {"preset" => "manual", "target" => target,
            "duration" => view.getValue().toString()}, "/tt/commit");
    }

    private function showAmount(view as AmountView) as Void {
        WatchUi.pushView(view, new AmountDelegate(method(:amountChosen), view), WatchUi.SLIDE_LEFT);
    }

    function committed(commitPath as String) as Void {
        MainMenu.ttActive = !_preset.equals("cancel");
    }

    function rebuild() as Void {
        WatchUi.switchToView(buildMenu(MainMenu.ttActive), new TtMenuDelegate(self), WatchUi.SLIDE_IMMEDIATE);
    }
}
