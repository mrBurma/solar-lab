import Toybox.Application;
import Toybox.Lang;
import Toybox.System;
import Toybox.Time.Gregorian;
import Toybox.Weather;

//! Current solar situation for the watch position: elevation, sunrise,
//! sunset and the fraction of daylight that has passed.
//!
//! Location source, in order:
//!   1. Weather.getCurrentConditions().observationLocationPosition
//!      (cached by the watch from the phone, no network request from us);
//!   2. the last known position saved in Application.Storage;
//!   3. a default (Moscow) until the first real position arrives.
class SolarState {

    const STORAGE_KEY = "loc";
    const DEFAULT_LAT = 55.7558;
    const DEFAULT_LON = 37.6173;

    var lat as Float = DEFAULT_LAT;
    var lon as Float = DEFAULT_LON;
    var hasFix as Boolean = false;        // false while the default location is used

    var elevation as Float = -6.0;        // degrees
    var riseMin as Float? = null;         // local minutes after midnight
    var setMin as Float? = null;
    var dayFraction as Float = 0.0;       // 0 at sunrise, 1 at sunset

    private var _lastLocationCheck as Number = -100;

    function initialize() {
        loadStoredLocation();
    }

    //! Recomputes everything. Call once per minute, never per frame.
    function refresh(clock as System.ClockTime, date as Gregorian.Info) as Void {
        var minuteOfDay = clock.hour * 60 + clock.min;
        if ((minuteOfDay - _lastLocationCheck).abs() >= 15) {
            _lastLocationCheck = minuteOfDay;
            updateLocation();
        }

        var tzHours = clock.timeZoneOffset / 3600.0;
        var doy = DateUtil.dayOfYear(date.year as Number, date.month as Number, date.day as Number);
        var minutes = minuteOfDay + clock.sec / 60.0;

        elevation = SolarMath.elevation(lat, lon, tzHours.toFloat(), doy, minutes.toFloat());

        var times = SolarMath.sunTimes(lat, lon, tzHours.toFloat(), doy);
        if (times != null) {
            riseMin = times[0];
            setMin = times[1];
            dayFraction = ((minutes - times[0]) / (times[1] - times[0])).toFloat();
        } else {
            riseMin = null;
            setMin = null;
            dayFraction = 0.5;
        }
    }

    //! Takes the position from the weather cache; saves it only when it moved,
    //! to avoid needless flash writes.
    private function updateLocation() as Void {
        if (!(Toybox has :Weather)) {
            return;
        }
        var conditions = Weather.getCurrentConditions();
        if (conditions == null) {
            return;
        }
        var position = conditions.observationLocationPosition;
        if (position == null) {
            return;
        }
        var deg = position.toDegrees();
        var newLat = deg[0].toFloat();
        var newLon = deg[1].toFloat();
        var moved = (newLat - lat).abs() > 0.05 || (newLon - lon).abs() > 0.05;
        lat = newLat;
        lon = newLon;
        if (moved || !hasFix) {
            Application.Storage.setValue(STORAGE_KEY, [newLat, newLon] as Array<Application.Storage.ValueType>);
        }
        hasFix = true;
    }

    private function loadStoredLocation() as Void {
        var saved = Application.Storage.getValue(STORAGE_KEY);
        if (saved instanceof Array && saved.size() == 2) {
            lat = (saved[0] as Numeric).toFloat();
            lon = (saved[1] as Numeric).toFloat();
            hasFix = true;
        }
    }
}
