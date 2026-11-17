import Toybox.Application;
import Toybox.Graphics;
import Toybox.Lang;
import Toybox.System;
import Toybox.Time;
import Toybox.Time.Gregorian;
import Toybox.WatchUi;

//! Main watch face view. Orchestrates layout, data, power state and rendering.
//! It never draws anything itself: drawing lives in FaceRenderer and AodRenderer.
//!
//! Update cadence:
//!   every minute      solar state, current health values, slots, summary
//!   every 5 minutes   weather line
//!   every 5 s (awake) heart rate
//!   one history job per frame while jobs are pending (ring, stress, pressure,
//!   night analysis, daily averages), so no frame does all the heavy work.
class SolarLabView extends WatchUi.WatchFace {

    private var _layout as LayoutManager?;
    private var _sky as SkyRenderer?;
    private var _power as PowerManager;
    private var _solar as SolarState;
    private var _health as HealthData;
    private var _baseline as Baseline;
    private var _readiness as Readiness;
    private var _advice as Advice;
    private var _weather as WeatherInfo;
    private var _slots as Array<SlotModel>;
    private var _phase as Number = Slots.DAY;

    private var _lastMinute as Number = -1;
    private var _lastWeather as Number = -9999;
    private var _forceRefresh as Boolean = true;
    private var _event as String? = null;      // last sentinel event, "03:12 SPO2 LOW 86%"
    // AMOLED needs the dim always-on screen against burn-in; a MIP screen is
    // always visible and has no burn-in, so it keeps the full face in low power
    private var _burnIn as Boolean = true;

    function initialize() {
        WatchFace.initialize();
        _power = new PowerManager();
        _solar = new SolarState();
        _health = new HealthData();
        _baseline = new Baseline();
        _readiness = new Readiness();
        _advice = new Advice();
        _weather = new WeatherInfo();
        _slots = [new SlotModel(), new SlotModel(), new SlotModel(), new SlotModel()] as Array<SlotModel>;
        var ds = System.getDeviceSettings();
        _burnIn = !(ds has :requiresBurnInProtection) || ds.requiresBurnInProtection;
    }

    //! Called once the screen size is known. All geometry is computed here, once.
    function onLayout(dc as Dc) as Void {
        var layout = new LayoutManager(dc);
        _layout = layout;
        _sky = new SkyRenderer(layout);
    }

    //! Called every minute in low-power mode and every second in high-power mode.
    function onUpdate(dc as Dc) as Void {
        var layout = _layout;
        var sky = _sky;
        if (layout == null || sky == null) {
            return;
        }

        var clock = System.getClockTime();
        var date = Gregorian.info(Time.now(), Time.FORMAT_SHORT);
        var now = Time.now().value();
        var tz = clock.timeZoneOffset;
        var minuteOfDay = clock.hour * 60 + clock.min;

        if (clock.min != _lastMinute || _forceRefresh) {
            _lastMinute = clock.min;
            _forceRefresh = false;
            _solar.refresh(clock, date);
            _health.refresh(now, tz);
            _phase = Slots.phase(_solar, minuteOfDay, _health.sleepMinute, _health.wakeMinute);
            _event = lastEvent(now, tz);
            if (now - _lastWeather >= 300) {
                _lastWeather = now;
                _weather.update(now, _health);
            }
            rebuild();
        } else if (!_power.isLowPower() && clock.sec % 5 == 0) {
            _health.refreshHeartRate(now);
            rebuild();
        }

        if (_health.runJob(now, tz, _baseline)) {
            rebuild();
            _weather.update(now, _health);     // pressure trend may have changed
        }

        if (_power.isLowPower() && _burnIn) {
            AodRenderer.draw(dc, layout, clock, date,
                _power.offsetX(clock.min), _power.offsetY(clock.min));
        } else {
            sky.update(_solar.elevation, _solar.dayFraction);
            FaceRenderer.draw(dc, layout, clock, date, _power.showSeconds(), sky, _solar,
                _health, _slots, _advice, _weather, _event);
        }
    }

    //! Metric kind under a screen point (icon ring or value), or -1.
    //! Used by the touch delegate.
    function slotKindAt(x as Number, y as Number) as Number {
        var l = _layout;
        if (l == null || y < l.iconY - l.iconR - l.px(6) || y > l.slotValueY + l.px(14)) {
            return -1;
        }
        var i = (x - l.slotX0 + l.slotPitch / 2) / l.slotPitch;
        if (x < l.slotX0 - l.slotPitch / 2 || i < 0 || i >= _slots.size()) {
            return -1;
        }
        return _slots[i].kind;
    }

    function health() as HealthData {
        return _health;
    }

    //! The user raised the wrist: switch to the full presentation, fresh data.
    function onExitSleep() as Void {
        _power.setLowPower(false);
        _forceRefresh = true;
        WatchUi.requestUpdate();
    }

    //! The watch went back to sleep: switch to the always-on presentation.
    function onEnterSleep() as Void {
        _power.setLowPower(true);
        WatchUi.requestUpdate();
    }

    //! Newest event logged by the background sentinel within 12 hours, as
    //! "03:12 SPO2 LOW 86%", or null.
    private function lastEvent(now as Number, tz as Number) as String? {
        var log = Application.Storage.getValue("events");
        if (!(log instanceof Array) || log.size() == 0) {
            return null;
        }
        var e = log[log.size() - 1];
        if (!(e instanceof Array) || e.size() < 2 || !(e[0] instanceof Number) || !(e[1] instanceof String)) {
            return null;
        }
        var t = e[0] as Number;
        if (now - t > 12 * 3600) {
            return null;
        }
        var m = (((t + tz) % 86400 + 86400) % 86400) / 60;
        return (m / 60).format("%02d") + ":" + (m % 60).format("%02d") + " " + (e[1] as String);
    }

    private function rebuild() as Void {
        var kinds = Slots.preset(_phase);
        for (var i = 0; i < _slots.size(); i++) {
            var kind = kinds[i];
            // No blood-oxygen data at all (Pulse Ox switched off): breathing instead
            if (kind == Slots.SPO2 && _health.spo2 == null && _health.spo2NightMin == null) {
                kind = Slots.RESP;
            }
            Slots.fill(_slots[i], kind, _health, _baseline, _phase);
        }
        _readiness.update(_health, _baseline);
        _advice.update(_phase, _readiness, _health, Time.now().value());
    }
}
