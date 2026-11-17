import Toybox.Application;
import Toybox.Lang;
import Toybox.Math;

//! Personal norm built on the watch itself.
//! Once per day (the first refresh after the night window ends) the face stores one
//! record of the night and the previous day in Application.Storage:
//!   [dayNumber, overnight BB charge, average daytime stress, night SpO2 minimum,
//!    night resting HR]
//! Missing values are stored as -1. The last DAYS records are kept (about 300 bytes).
//! After MIN_DAYS records, a value further than 2 sigma from the personal mean is
//! flagged as an anomaly. Until then resting HR is compared with Garmin's own
//! average (UserProfile.averageRestingHeartRate).
//! Limitation: history accumulates only while this watch face is active.
class Baseline {

    const STORAGE_KEY = "base";
    const DAYS = 14;
    const MIN_DAYS = 7;

    enum {
        CHARGE = 1,
        STRESS = 2,
        SPO2 = 3,
        RHR = 4
    }

    private var _records as Array<Array<Number>> = [] as Array<Array<Number>>;

    function initialize() {
        var saved = Application.Storage.getValue(STORAGE_KEY);
        if (saved instanceof Array) {
            for (var i = 0; i < saved.size(); i++) {
                var r = saved[i];
                if (r instanceof Array && r.size() == 5) {
                    _records.add(r as Array<Number>);
                }
            }
        }
    }

    //! Day number of the newest record, or -1 when empty.
    function lastDay() as Number {
        return (_records.size() > 0) ? _records[_records.size() - 1][0] : -1;
    }

    function count() as Number {
        return _records.size();
    }

    //! Appends one record for dayNumber (days since epoch), once per day.
    function store(dayNumber as Number, charge as Number?, stressAvg as Number?,
                   spo2Min as Number?, rhr as Number?) as Void {
        if (dayNumber == lastDay()) {
            return;
        }
        _records.add([dayNumber, orMissing(charge), orMissing(stressAvg), orMissing(spo2Min), orMissing(rhr)]);
        while (_records.size() > DAYS) {
            _records = _records.slice(1, null);
        }
        Application.Storage.setValue(STORAGE_KEY, _records as Array<Application.Storage.ValueType>);
    }

    //! Personal mean of a field, or null with too little history.
    function mean(field as Number) as Float? {
        var stats = statsOf(field);
        return (stats != null) ? stats[0] : null;
    }

    //! True when value is further than 2 sigma from the personal mean.
    //! A floor on sigma keeps a very stable history from flagging tiny changes.
    function isAnomaly(field as Number, value as Number?) as Boolean {
        if (value == null) {
            return false;
        }
        var stats = statsOf(field);
        if (stats == null) {
            return false;
        }
        var sigma = stats[1];
        var floor = 5.0;
        if (field == SPO2) {
            floor = 1.0;
        } else if (field == RHR) {
            floor = 2.0;
        }
        if (sigma < floor) {
            sigma = floor;
        }
        return (value - stats[0]).abs() > 2.0 * sigma;
    }

    //! [mean, standard deviation] over stored values, or null below MIN_DAYS.
    private function statsOf(field as Number) as [Float, Float]? {
        var n = 0;
        var sum = 0.0;
        var sumSq = 0.0;
        for (var i = 0; i < _records.size(); i++) {
            var v = _records[i][field];
            if (v >= 0) {
                n += 1;
                sum += v;
                sumSq += v * v;
            }
        }
        if (n < MIN_DAYS) {
            return null;
        }
        var m = sum / n;
        var variance = sumSq / n - m * m;
        if (variance < 0.0) {
            variance = 0.0;
        }
        return [m.toFloat(), Math.sqrt(variance).toFloat()];
    }

    private function orMissing(v as Number?) as Number {
        return (v != null) ? v : -1;
    }
}
