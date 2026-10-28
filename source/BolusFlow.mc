import Toybox.Attention;
import Toybox.Lang;
import Toybox.System;
import Toybox.Timer;
import Toybox.WatchUi;

// Bolus from the watch, the same two-step idea as the temp target: AAPS
// calculates and describes the bolus (/qw/prepare, /wizard/prepare or
// /treatment/prepare), and only a 2 s hold of START sends /bolus/commit. The
// watch never computes insulin; for a treatment it only passes on the amount
// chosen, and AAPS rounds and limits it and says what it will really give.
// When AAPS says the prepared dose is 0 U (carbs only, from any entry), no
// insulin is given, so one START press confirms it and there is no stop screen.
//
// View stack: main menu, then the Quick Wizard list, the carbs picker (the
// meal type menu) and the carb time and percentage pickers, or the treatment
// insulin and carbs pickers, then the status/confirm/stop screens, which
// replace each other on top.
class BolusFlow {
    // AAPS keeps the prepared id for 60 s; half of that leaves room for the
    // commit request to arrive well before AAPS drops it.
    private const CONFIRM_MS = 30000;
    private const HOLD_MS = 2000;
    // About 15 updates a second is smooth enough for the ring and cheap.
    private const TICK_MS = 66;
    private const RESULT_MS = 3000;
    // The stop screen asks AAPS whether the bolus is still running at this
    // interval; the first ask also waits this long, so AAPS has started it.
    private const POLL_MS = 3000;
    // Well beyond any bolus a real pump delivers (6.8 U takes about 4.5 min,
    // slower pumps and large boluses take longer), so the screen only gives
    // up when AAPS cannot be asked at all.
    private const STOP_MAX_MS = 1200000;
    // Nearest fr955 palette colours to the AAPS night theme insulin (0xFF67DFE8)
    // and carbs (0xFFFFAE01) colours.
    private const INSULIN_COLOR = 0x55FFFF;
    private const CARBS_COLOR = 0xFFAA00;
    // Used when /status did not give the limits; AAPS limits the amount anyway.
    private const DEFAULT_MAX_INSULIN = 1000;
    private const DEFAULT_MAX_CARBS = 200;
    // Hundredths of a unit; 0.05 U is the finest step most pumps give.
    private const DEFAULT_INSULIN_STEP = 5;
    private const CARBS_STEP = 5;
    // The bolus wizard's limits in AAPS; it refuses anything outside them.
    private const CARB_TIME_MAX = 60;
    private const CARB_TIME_STEP = 5;
    private const PERCENT_MIN = 10;
    private const PERCENT_MAX = 200;
    private const PERCENT_STEP = 5;
    private const DEFAULT_PERCENT = 100;

    private const ENTRY_QW = 0;
    private const ENTRY_WIZARD = 1;
    private const ENTRY_TREATMENT = 2;

    private var _id as String?;
    private var _status as StatusView?;
    private var _confirm as BolusConfirmView?;
    private var _timer as Timer.Timer = new Timer.Timer();
    private var _tick as Timer.Timer = new Timer.Timer();
    private var _holdStart as Number?;
    // Views of this flow below the top screen (QW list or carbs picker).
    private var _below as Number = 0;
    // Set once a bolus may have been given, or the confirm screen expired:
    // closing then also removes the QW list or carbs picker, so the user lands
    // on the main menu and is not one START away from choosing the same bolus
    // again, nor back in a picker that has nothing to do with the timeout.
    private var _toMenu as Boolean = false;
    // Stop screen state: when it was shown, whether its /status answers still
    // matter, and whether the stop that is out came from that screen (then a
    // failed stop goes back to it instead of ending the flow).
    private var _stopShown as Number = 0;
    private var _polling as Boolean = false;
    private var _stopFromScreen as Boolean = false;
    // Which entry asked /status (ENTRY_...).
    private var _entry as Number = ENTRY_QW;
    // Treatment: insulin in hundredths of a unit, the limits, pump step and
    // settings from /status, and whether the insulin screen was shown (it is a
    // view below the carbs screen then). _carbsOnly is set by every prepare
    // answer: true when no insulin will be given.
    private var _insulin as Number = 0;
    private var _maxInsulin as Number = DEFAULT_MAX_INSULIN;
    private var _insulinStep as Number = DEFAULT_INSULIN_STEP;
    private var _maxCarbs as Number = DEFAULT_MAX_CARBS;
    private var _carbsEnabled as Boolean = true;
    private var _insulinShown as Boolean = true;
    private var _carbsOnly as Boolean = false;
    // Bolus wizard: what was chosen on the earlier screens, and AAPS' default
    // percentage from the entry /status, which the percentage screen starts on.
    private var _wizardCarbs as Number = 0;
    private var _mealType as String?;
    private var _carbTime as Number = 0;
    private var _wizardPercent as Number = DEFAULT_PERCENT;

    // ---- Entry

    // All bolus entries ask /status first: when a bolus is still running (the
    // widget was left during it), the stop screen is shown instead, so the
    // user can stop it rather than start choosing the next one.
    function openQuickWizard() as Void {
        open(ENTRY_QW);
    }

    function openWizard() as Void {
        open(ENTRY_WIZARD);
    }

    function openTreatment() as Void {
        open(ENTRY_TREATMENT);
    }

    private function open(entry as Number) as Void {
        if (Aaps.busy) {
            return;
        }
        _below = 0;
        _entry = entry;
        pushStatus(Rez.Strings.Loading);
        Aaps.send("/status", {}, method(:onEntryStatus));
    }

    // Without a usable answer the flow goes on as normal; AAPS itself refuses
    // a new bolus while one is running.
    function onEntryStatus(code as Number, data as Dictionary or String or Null) as Void {
        Aaps.busy = false;
        Aaps.log("entry status " + code);
        var ok = Aaps.isOk(code, data);
        if (ok && (data as Dictionary)["bolusRunning"] == true) {
            showStop(false, null);
        } else if (_entry == ENTRY_QW) {
            Aaps.send("/qw/list", {}, method(:onList));
        } else if (_entry == ENTRY_WIZARD) {
            _wizardPercent = DEFAULT_PERCENT;
            var percent = ok ? (data as Dictionary)["wizardPercent"] : null;
            if (percent instanceof Number && percent >= PERCENT_MIN && percent <= PERCENT_MAX) {
                _wizardPercent = percent;
            }
            showAmount(new AmountView(false, DEFAULT_MAX_CARBS, CARBS_STEP, null), false);
        } else {
            showTreatment(ok ? data as Dictionary : null);
        }
    }

    // START on any amount screen.
    function amountChosen(view as AmountView) as Void {
        if (_entry != ENTRY_TREATMENT) {
            var title = view.getTitle();
            if (title == Rez.Strings.CarbTime) {
                carbTimeChosen(view.getValue());
            } else if (title == Rez.Strings.Percentage) {
                prepareWizard(view.getValue());
            } else {
                carbsChosen(view.getValue());
            }
        } else if (view.isInsulin()) {
            insulinChosen(view.getValue());
        } else {
            treatmentCarbsChosen(view);
        }
    }

    // Replaces the loading screen, or goes on top for the treatment carbs
    // after the insulin screen, so BACK there returns to the insulin.
    private function showAmount(view as AmountView, push as Boolean) as Void {
        if (push) {
            WatchUi.pushView(view, new AmountDelegate(method(:amountChosen), view), WatchUi.SLIDE_LEFT);
        } else {
            _status = null;
            WatchUi.switchToView(view, new AmountDelegate(method(:amountChosen), view), WatchUi.SLIDE_LEFT);
        }
    }

    // ---- Quick Wizard

    function onList(code as Number, data as Dictionary or String or Null) as Void {
        Aaps.busy = false;
        Aaps.log("qw list " + code);
        if (Aaps.isOk(code, data)) {
            var items = (data as Dictionary)["items"];
            if (items instanceof Array) {
                var menu = new WatchUi.Menu2({:title => Aaps.str(Rez.Strings.QuickWizard)});
                var count = 0;
                for (var i = 0; i < items.size(); i++) {
                    var it = items[i];
                    if (it instanceof Dictionary && it["guid"] instanceof String && it["name"] instanceof String) {
                        // The guid is the menu id, so the choice goes back to AAPS unchanged.
                        menu.addItem(new WatchUi.MenuItem(it["name"] as String, null, it["guid"] as String, null));
                        count++;
                    }
                }
                if (count == 0) {
                    showResult(Aaps.str(Rez.Strings.NoQw));
                } else {
                    _status = null;
                    WatchUi.switchToView(menu, new QwMenuDelegate(self), WatchUi.SLIDE_IMMEDIATE);
                }
                return;
            }
        }
        showResult(Aaps.errorText(code, data, Aaps.str(Rez.Strings.UnknownAnswer)));
    }

    function prepareQuickWizard(guid as String) as Void {
        if (Aaps.busy) {
            return;
        }
        _below = 1;
        pushStatus(Rez.Strings.Loading);
        Aaps.send("/qw/prepare", {"guid" => guid}, method(:onPrepare));
    }

    // ---- Bolus wizard

    // START on the carbs screen. The meal type only changes how AAPS splits
    // carbs, so with 0 g there is nothing to choose.
    function carbsChosen(carbs as Number) as Void {
        if (Aaps.busy) {
            return;
        }
        _wizardCarbs = carbs;
        if (carbs == 0) {
            mealChosen(null);
            return;
        }
        // Bread first, so pressing START straight through gives the plain wizard (all carbs now).
        var menu = new WatchUi.Menu2({:title => carbs + " g"});
        menu.addItem(mealItem(Rez.Strings.Bread, Rez.Strings.BreadSub, "bread", Rez.Drawables.MealBread));
        menu.addItem(mealItem(Rez.Strings.Cake, Rez.Strings.CakeSub, "cake", Rez.Drawables.MealCake));
        menu.addItem(mealItem(Rez.Strings.Pizza, Rez.Strings.PizzaSub, "pizza", Rez.Drawables.MealPizza));
        WatchUi.pushView(menu, new MealMenuDelegate(self), WatchUi.SLIDE_LEFT);
    }

    private function mealItem(label as ResourceId, sub as ResourceId, id as String, icon as ResourceId) as WatchUi.IconMenuItem {
        return new WatchUi.IconMenuItem(Aaps.str(label), Aaps.str(sub), id, new MenuIcon(icon), null);
    }

    // type is the meal type AAPS expects (bread, cake, pizza) or null for 0 g.
    // Carb time and percentage are always asked, starting on AAPS' own
    // defaults, so only START presses keep the plain wizard; BACK on each
    // goes one screen back.
    function mealChosen(type as String?) as Void {
        if (Aaps.busy) {
            return;
        }
        _mealType = type;
        var view = new AmountView(false, CARB_TIME_MAX, CARB_TIME_STEP, null);
        view.setWhole(Rez.Strings.CarbTime, Rez.Strings.CarbTimeSub, "min", -CARB_TIME_MAX, 0);
        showAmount(view, true);
    }

    private function carbTimeChosen(carbTime as Number) as Void {
        if (Aaps.busy) {
            return;
        }
        _carbTime = carbTime;
        var view = new AmountView(false, PERCENT_MAX, PERCENT_STEP, null);
        view.setWhole(Rez.Strings.Percentage, null, "%", PERCENT_MIN, _wizardPercent);
        showAmount(view, true);
    }

    private function prepareWizard(percent as Number) as Void {
        if (Aaps.busy) {
            return;
        }
        var type = _mealType;
        // Carbs, carb time and percentage screens, and the meal type menu
        // when there are carbs, are removed after a bolus.
        _below = type == null ? 3 : 4;
        pushStatus(Rez.Strings.Loading);
        var params = {"carbs" => _wizardCarbs.toString(), "carbTime" => _carbTime.toString(),
            "percent" => percent.toString()} as Dictionary<Object, Object>;
        if (type != null) {
            params["type"] = type;
        }
        Aaps.send("/wizard/prepare", params, method(:onPrepare));
    }

    // ---- Treatment

    // The limits and settings come from this /status, so they are fresh.
    // Without them the screens use defaults and both are shown; AAPS refuses
    // what its settings do not allow and limits the amounts itself.
    private function showTreatment(d as Dictionary?) as Void {
        var maxInsulin = DEFAULT_MAX_INSULIN;
        _insulinStep = DEFAULT_INSULIN_STEP;
        _maxCarbs = DEFAULT_MAX_CARBS;
        _carbsEnabled = true;
        var bolusEnabled = true;
        if (d != null) {
            // The pump's own step, so every press is an amount the pump can
            // give. Rounded to whole hundredths, the finest the watch keeps.
            var step = d["bolusStep"];
            if (Aaps.isNumeric(step)) {
                var hundredths = ((step as Numeric).toFloat() * 100 + 0.5f).toNumber();
                if (hundredths > 0) {
                    _insulinStep = hundredths;
                }
            }
            var maxBolus = d["maxBolus"];
            if (Aaps.isNumeric(maxBolus)) {
                maxInsulin = ((maxBolus as Numeric).toFloat() * 100 + 0.5f).toNumber();
            }
            var maxCarbs = d["maxCarbs"];
            if (maxCarbs instanceof Number || maxCarbs instanceof Long) {
                var max = (maxCarbs as Numeric).toNumber() / CARBS_STEP * CARBS_STEP;
                _maxCarbs = max < 0 ? 0 : max;
            }
            if (d["bolusEnabled"] instanceof Boolean) {
                bolusEnabled = d["bolusEnabled"] as Boolean;
            }
            if (d["carbsEnabled"] instanceof Boolean) {
                _carbsEnabled = d["carbsEnabled"] as Boolean;
            }
        }
        // Down to a whole number of steps, so UP never goes above AAPS' limit.
        maxInsulin = maxInsulin / _insulinStep * _insulinStep;
        _maxInsulin = maxInsulin < 0 ? 0 : maxInsulin;
        _insulin = 0;
        // Bolus off in AAPS: insulin can only be 0, so its screen is skipped.
        _insulinShown = bolusEnabled;
        showAmount(bolusEnabled ? new AmountView(true, _maxInsulin, _insulinStep, INSULIN_COLOR)
            : new AmountView(false, _maxCarbs, CARBS_STEP, CARBS_COLOR), false);
    }

    private function insulinChosen(insulin as Number) as Void {
        if (Aaps.busy) {
            return;
        }
        _insulin = insulin;
        // Carbs off in AAPS: with insulin chosen there is nothing to ask for.
        if (!_carbsEnabled && insulin > 0) {
            prepareTreatment(0, 1);
            return;
        }
        showAmount(new AmountView(false, _maxCarbs, CARBS_STEP, CARBS_COLOR), true);
    }

    private function treatmentCarbsChosen(view as AmountView) as Void {
        if (Aaps.busy) {
            return;
        }
        var carbs = view.getValue();
        if (_insulin == 0 && carbs == 0) {
            view.setNote(Aaps.str(Rez.Strings.ChooseAmount));
            return;
        }
        prepareTreatment(carbs, _insulinShown ? 2 : 1);
    }

    // below is the number of picker screens to remove after a treatment.
    private function prepareTreatment(carbs as Number, below as Number) as Void {
        _below = below;
        pushStatus(Rez.Strings.Loading);
        // Built from whole hundredths, so the decimal mark is always "." and
        // there are always two decimals, whatever the watch language.
        var insulin = (_insulin / 100).toString() + "." + (_insulin % 100).format("%02d");
        Aaps.send("/treatment/prepare", {"insulin" => insulin, "carbs" => carbs.toString()}, method(:onPrepare));
    }

    // START on the carbs-only confirm screen.
    function confirmCarbs() as Void {
        if (_carbsOnly) {
            commit();
        }
    }

    // ---- Confirm (shared by Quick Wizard, bolus wizard and treatment)

    function onPrepare(code as Number, data as Dictionary or String or Null) as Void {
        Aaps.busy = false;
        Aaps.log("bolus prepare " + code);
        _carbsOnly = false;
        if (Aaps.isOk(code, data)) {
            var id = (data as Dictionary)["id"];
            var lines = (data as Dictionary)["lines"];
            // "insulin" is the dose AAPS calculated or chose. Only an explicit
            // 0 takes the one-press way; without the field a treatment with no
            // insulin chosen is still carbs only, anything else needs the hold.
            var dose = (data as Dictionary)["insulin"];
            if (Aaps.isNumeric(dose)) {
                _carbsOnly = (dose as Numeric).toFloat() == 0.0f;
            } else {
                _carbsOnly = _entry == ENTRY_TREATMENT && _insulin == 0;
            }
            // Without lines the user would confirm a bolus AAPS did not
            // describe, so that is shown as an unknown answer instead.
            if (id instanceof String && lines instanceof Array && lines.size() > 0) {
                _id = id;
                _status = null;
                if (_carbsOnly) {
                    WatchUi.switchToView(new ConfirmView(Aaps.toLines(lines)), new CarbsConfirmDelegate(self), WatchUi.SLIDE_IMMEDIATE);
                } else {
                    var view = new BolusConfirmView(Aaps.toLines(lines), method(:holdCancel));
                    _confirm = view;
                    WatchUi.switchToView(view, new BolusConfirmDelegate(self), WatchUi.SLIDE_IMMEDIATE);
                }
                startTimer(method(:onExpired), CONFIRM_MS);
                return;
            }
        }
        // A refused bolus wizard (e.g. "No insulin required") answers the whole
        // calculation, not the percentage, so going back one screen would only
        // invite the same answer; the main menu is where to choose again.
        if (_entry == ENTRY_WIZARD) {
            _toMenu = true;
        }
        showResult(Aaps.errorText(code, data, Aaps.str(Rez.Strings.UnknownAnswer)));
    }

    // START went down on the confirm screen. A press that was already down when
    // the screen appeared never reaches here, so every bolus needs a fresh press.
    function holdStart() as Void {
        if (_id == null || Aaps.busy || _holdStart != null) {
            return;
        }
        _holdStart = System.getTimer();
        _tick.start(method(:onTick), TICK_MS, true);
    }

    // START came up before 2 s, or the confirm screen was covered: nothing is
    // sent and the ring starts over.
    function holdCancel() as Void {
        if (_holdStart == null) {
            return;
        }
        stopHold();
        setProgress(0.0f);
    }

    function onTick() as Void {
        var start = _holdStart;
        if (start == null) {
            return;
        }
        var progress = (System.getTimer() - start).toFloat() / HOLD_MS;
        if (progress < 1.0f) {
            setProgress(progress);
            return;
        }
        stopHold();
        // A tick that was already due when the screen was covered must not
        // send; onHide normally ends the hold before that.
        var view = _confirm;
        if (view == null || !view.isVisible()) {
            return;
        }
        setProgress(1.0f);
        // Felt confirmation that the hold counted, since the screen changes
        // while the user is still looking at the ring.
        if (Attention has :vibrate) {
            Attention.vibrate([new Attention.VibeProfile(60, 150)] as Array<Attention.VibeProfile>);
        }
        commit();
    }

    private function commit() as Void {
        var id = _id;
        if (Aaps.busy || id == null) {
            return;
        }
        _id = null;
        _confirm = null;
        _timer.stop();
        var status = new StatusView(Aaps.str(Rez.Strings.Sending));
        _status = status;
        WatchUi.switchToView(status, new StatusDelegate(method(:close)), WatchUi.SLIDE_IMMEDIATE);
        // The id is passed on as the exact string received: it does not fit in
        // a 32-bit Number, so parsing it would corrupt it.
        Aaps.send("/bolus/commit", {"id" => id}, method(:onCommit));
    }

    function onCommit(code as Number, data as Dictionary or String or Null) as Void {
        Aaps.busy = false;
        Aaps.log("bolus commit " + code);
        if (Aaps.isOk(code, data)) {
            _toMenu = true;
            // Carbs alone: nothing to stop, so a check mark and back to the menu.
            if (_carbsOnly) {
                showDone(null);
            } else {
                showStop(true, null);
            }
            return;
        }
        // Only answers that prove AAPS gave nothing get a plain error, and the
        // user goes back one step to choose again. Anything else may hide a
        // bolus that was given, so nothing is retried: the text stays until
        // BACK, and then the stop screen follows in case the bolus is running
        // (not for carbs alone, which can not have started a bolus).
        if (Aaps.provedNothingDone(code, data)) {
            showResult(Aaps.errorText(code, data, Aaps.str(Rez.Strings.Error)));
            return;
        }
        _toMenu = true;
        _timer.stop();
        var status = new StatusView(Aaps.str(Rez.Strings.UnknownBolus) + "\n(" + code + ")");
        _status = status;
        WatchUi.switchToView(status, new StatusDelegate(_carbsOnly ? method(:close) : method(:afterUnknown)), WatchUi.SLIDE_IMMEDIATE);
        // Felt as well as seen, since the user may already have looked away.
        if (Attention has :vibrate) {
            Attention.vibrate([new Attention.VibeProfile(100, 400), new Attention.VibeProfile(0, 200),
                new Attention.VibeProfile(100, 400), new Attention.VibeProfile(0, 200),
                new Attention.VibeProfile(100, 400)] as Array<Attention.VibeProfile>);
        }
    }

    // BACK on the unknown text. No check mark on the stop screen: the watch
    // does not know whether the bolus was given.
    function afterUnknown() as Void {
        showStop(false, null);
    }

    // Back to the main menu afterwards: the user stopped dealing with this
    // bolus, so landing in the picker or list would only invite a stale choice.
    function onExpired() as Void {
        _toMenu = true;
        stopHold();
        _id = null;
        _confirm = null;
        var status = new StatusView(Aaps.str(Rez.Strings.Expired));
        _status = status;
        WatchUi.switchToView(status, new StatusDelegate(method(:close)), WatchUi.SLIDE_IMMEDIATE);
        startTimer(method(:close), RESULT_MS);
    }

    // ---- Stop

    // From the main menu: one press on the menu item is enough, because
    // stopping can never give insulin. Sent even while a late /status poll
    // from a closed stop screen is still out.
    function stopBolus() as Void {
        if (Aaps.stopping) {
            return;
        }
        _below = 0;
        _stopFromScreen = false;
        pushStatus(Rez.Strings.Sending);
        Aaps.sendStop(method(:onStop));
    }

    // Replaces the screen on top with the stop screen, which polls /status
    // until AAPS says no bolus is running. sent is true right after AAPS
    // confirmed this bolus, so the screen can show that it went through.
    // error is set when a stop from this screen failed; the time limit then
    // still counts from when the screen was first shown.
    private function showStop(sent as Boolean, error as String?) as Void {
        _status = null;
        WatchUi.switchToView(new StopView(sent, error), new StopDelegate(self), WatchUi.SLIDE_IMMEDIATE);
        if (error == null) {
            _stopShown = System.getTimer();
        }
        _polling = true;
        // The flow's single timer drives the polling, so no extra timer is
        // needed; close() stops it on every way out.
        _timer.stop();
        _timer.start(method(:onPoll), POLL_MS, true);
    }

    function onPoll() as Void {
        if (System.getTimer() - _stopShown > STOP_MAX_MS) {
            close();
            return;
        }
        // A request still out is simply skipped; the next tick asks again.
        if (!Aaps.waiting()) {
            Aaps.send("/status", {}, method(:onPollStatus));
        }
    }

    function onPollStatus(code as Number, data as Dictionary or String or Null) as Void {
        Aaps.busy = false;
        Aaps.log("status " + code);
        // Not polling any more (START was pressed, or the screen was left):
        // a late answer must not replace the stop or its result.
        if (!_polling) {
            return;
        }
        // Only a clear "not running" closes the screen; errors keep it up.
        // Straight to the main menu without a message: "No bolus running"
        // read like "nothing was given".
        if (Aaps.isOk(code, data) && (data as Dictionary)["bolusRunning"] == false) {
            close();
        }
    }

    // START on the stop screen. The stop is sent at once, even if a /status
    // poll is out; stopping polling first makes that poll's answer harmless.
    function stopFromScreen() as Void {
        if (!_polling || Aaps.stopping) {
            return;
        }
        _polling = false;
        _stopFromScreen = true;
        _timer.stop();
        var status = new StatusView(Aaps.str(Rez.Strings.Sending));
        _status = status;
        WatchUi.switchToView(status, new StatusDelegate(method(:close)), WatchUi.SLIDE_IMMEDIATE);
        Aaps.sendStop(method(:onStop));
    }

    function onStop(code as Number, data as Dictionary or String or Null) as Void {
        Aaps.stopping = false;
        Aaps.log("bolus stop " + code);
        var text = Aaps.isOk(code, data) ? (data as Dictionary)["text"] : null;
        if (text instanceof String && text.length() > 0) {
            if (text.equals("Bolus stopped")) {
                // Only a stop that hit a running bolus gets the check mark;
                // "No bolus running" is information, not a done action.
                showDone(text);
            } else {
                showResult(text);
            }
            return;
        }
        var error = Aaps.errorText(code, data, Aaps.str(Rez.Strings.UnknownCheck));
        // The bolus may still be running: back to the stop screen, so START
        // can try again and polling shows when it ends.
        if (_stopFromScreen) {
            showStop(false, error);
        } else {
            showResult(error);
        }
    }

    // ---- Common

    // Ends every screen of this flow. Normally one step back; after a bolus
    // that may have been given, back to the main menu.
    function close() as Void {
        _timer.stop();
        _polling = false;
        stopHold();
        _id = null;
        _status = null;
        _confirm = null;
        var pops = 1 + (_toMenu ? _below : 0);
        _toMenu = false;
        _below = 0;
        for (var i = 0; i < pops; i++) {
            WatchUi.popView(WatchUi.SLIDE_IMMEDIATE);
        }
    }

    private function stopHold() as Void {
        _tick.stop();
        _holdStart = null;
    }

    private function setProgress(progress as Float) as Void {
        var view = _confirm;
        if (view != null) {
            view.setProgress(progress);
        }
    }

    private function pushStatus(text as ResourceId) as Void {
        var status = new StatusView(Aaps.str(text));
        _status = status;
        WatchUi.pushView(status, new StatusDelegate(method(:close)), WatchUi.SLIDE_IMMEDIATE);
    }

    private function showResult(text as String) as Void {
        var status = _status;
        if (status != null) {
            status.setText(text);
        }
        startTimer(method(:close), RESULT_MS);
    }

    private function showDone(text as String?) as Void {
        var status = _status;
        if (status != null) {
            status.setDone(text);
        }
        startTimer(method(:close), RESULT_MS);
    }

    private function startTimer(callback as Method() as Void, ms as Number) as Void {
        _timer.stop();
        _timer.start(callback, ms, false);
    }
}

class QwMenuDelegate extends WatchUi.Menu2InputDelegate {
    private var _flow as BolusFlow;

    function initialize(flow as BolusFlow) {
        Menu2InputDelegate.initialize();
        _flow = flow;
    }

    function onSelect(item as WatchUi.MenuItem) as Void {
        _flow.prepareQuickWizard(item.getId() as String);
    }
}

// BACK is left to Menu2's default, which returns to the carbs screen.
class MealMenuDelegate extends WatchUi.Menu2InputDelegate {
    private var _flow as BolusFlow;

    function initialize(flow as BolusFlow) {
        Menu2InputDelegate.initialize();
        _flow = flow;
    }

    // The item id is the meal type AAPS expects, so no mapping is needed.
    function onSelect(item as WatchUi.MenuItem) as Void {
        _flow.mealChosen(item.getId() as String);
    }
}
