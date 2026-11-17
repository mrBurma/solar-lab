import Toybox.Lang;
import Toybox.System;
import Toybox.Time;
import Toybox.Weather;

//! Weather line under the horizon, in words: "3°  FEELS 0°  UV 5  P↑"
//! (Russian: "3°  КАК 0°  UV 5  Д↑").
//! Only the weather cached by the watch is read; the face makes no network
//! requests. Parts are kept separately so each can carry its own status colour:
//!   FEELS   feels-like ("3° FEELS 0°"), shown only when it differs by 2° or more
//!   UV      shown from 3; amber from 6, coral from 8 (WHO bands)
//!   P       barometric tendency (pressure) over 3 h (altitude-corrected): an arrow from
//!           1 hPa, a double arrow in amber from 3.6 hPa (a front);
//!           nothing when steady. The hPa value itself is not shown.
//! Conditions older than 3 hours are drawn grey.
class WeatherInfo {

    const STALE = 3 * 3600;

    var parts as Array<String> = [] as Array<String>;
    var levels as Array<Number> = [] as Array<Number>;
    var stale as Boolean = false;

    function initialize() {
    }

    function update(now as Number, h as HealthData) as Void {
        parts = [] as Array<String>;
        levels = [] as Array<Number>;
        stale = false;

        var c = (Toybox has :Weather) ? Weather.getCurrentConditions() : null;
        if (c != null) {
            var obs = c.observationTime;
            if (obs != null && now - obs.value() > STALE) {
                stale = true;
            }
            var t = c.temperature;
            if (t != null) {
                add(temperature(t.toFloat()) + "°", Status.NORM);
                var f = c.feelsLikeTemperature;
                if (f != null && (f - t.toFloat()).abs() >= 2.0) {
                    add(Tr.f(Rez.Strings.WxFeels, [temperature(f)]), Status.NORM);
                }
            }
            var uv = c.uvIndex;
            if (uv != null && uv >= 3.0) {
                var level = Status.NORM;
                if (uv >= 8.0) {
                    level = Status.ALERT;
                } else if (uv >= 6.0) {
                    level = Status.WARN;
                }
                add("UV " + uv.toNumber().format("%d"), level);
            }
        }

        var trend = h.pressureTrend;
        if (trend != null && trend.abs() >= 1.0) {
            if (trend.abs() >= 3.6) {
                add(Tr.s(Rez.Strings.WxPressure) + ((trend > 0) ? "↑↑" : "↓↓"), Status.WARN);
            } else {
                add(Tr.s(Rez.Strings.WxPressure) + ((trend > 0) ? "↑" : "↓"), Status.NORM);
            }
        }
    }

    private function add(text as String, level as Number) as Void {
        parts.add(text);
        levels.add(level);
    }

    //! Rounded temperature in the units chosen on the watch, typographic minus.
    private function temperature(celsius as Float) as String {
        var v = celsius;
        if (System.getDeviceSettings().temperatureUnits == System.UNIT_STATUTE) {
            v = celsius * 9.0 / 5.0 + 32.0;
        }
        var n = (v >= 0.0) ? (v + 0.5).toNumber() : -((-v + 0.5).toNumber());
        return (n < 0) ? "−" + (-n).format("%d") : n.format("%d");
    }
}
