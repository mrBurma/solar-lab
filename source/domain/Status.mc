import Toybox.Lang;

//! Status classification of single values: zone word + severity level.
//! Pure functions, no Toybox API calls, so every threshold is in one place.
//!
//! Levels map to colours in the renderer:
//!   GOOD (cyan)  NORM (white)  WARN (amber)  ALERT (coral)  NONE (grey)
//! Thresholds: Body Battery and stress use Garmin's published bands; heart rate
//! uses the user's own zones and resting HR; respiration and SpO2 use typical
//! resting ranges (an orientation, not a medical measurement).
module Status {

    enum {
        GOOD = 0,
        NORM = 1,
        WARN = 2,
        ALERT = 3,
        NONE = 4
    }

    //! Body Battery, Garmin bands: 0-25 LOW, 26-50 MED, 51-75 HIGH, 76-100 PEAK.
    function bodyBattery(v as Number) as [String, Number] {
        if (v <= 25) { return ["LOW", ALERT]; }
        if (v <= 50) { return ["MED", WARN]; }
        if (v <= 75) { return ["HIGH", NORM]; }
        return ["PEAK", GOOD];
    }

    //! Stress, Garmin bands: 0-25 REST, 26-50 LOW, 51-75 MED, 76-100 HIGH.
    function stress(v as Number) as [String, Number] {
        if (v <= 25) { return ["REST", GOOD]; }
        if (v <= 50) { return ["LOW", NORM]; }
        if (v <= 75) { return ["MED", WARN]; }
        return ["HIGH", ALERT];
    }

    //! Current heart rate against the user's resting HR and HR zones.
    //! zones = UserProfile.getHeartRateZones(): [z1 min, z1 max, z2 max, z3 max, z4 max, z5 max].
    function heartRate(v as Number, rhr as Number?, zones as Array<Number>?) as [String, Number] {
        var restTop = (rhr != null) ? rhr + 10 : 70;
        var activeTop = 110;
        var cardioTop = 150;
        if (zones != null && zones.size() >= 6) {
            activeTop = zones[1];
            cardioTop = zones[3];
        }
        if (v <= restTop) { return ["REST", GOOD]; }
        if (v <= activeTop) { return ["ACTIVE", NORM]; }
        if (v <= cardioTop) { return ["CARDIO", NORM]; }
        return ["PEAK", WARN];
    }

    //! Resting HR today against Garmin's 7-day average: the delta is the status.
    //! +4 bpm and more is a common early sign of fatigue, stress or illness.
    function restingDelta(delta as Number) as [String, Number] {
        var text = (delta > 0) ? "+" + delta.format("%d") : (delta < 0 ? "−" + (-delta).format("%d") : "±0");
        if (delta >= 7) { return [text, ALERT]; }
        if (delta >= 4) { return [text, WARN]; }
        if (delta <= 0) { return [text, GOOD]; }
        return [text, NORM];
    }

    //! Breaths per minute at rest. 12-20 is the textbook awake range, but relaxed
    //! and sleeping adults commonly breathe 10-12 (wrist values are averaged), so
    //! only 9 and below counts as low.
    function respiration(v as Number) as [String, Number] {
        if (v <= 9) { return ["LOW", WARN]; }
        if (v <= 20) { return ["NORM", GOOD]; }
        return ["HIGH", WARN];
    }

    //! Blood oxygen from the wrist sensor: indicative only.
    //! Blood oxygen from the WRIST sensor. Reflectance readings at the wrist run
    //! several points below a fingertip oximeter (checked by the user: wrist 91,
    //! finger 99-100), so the clinical 95 % line would keep a healthy reading
    //! amber all day. Bands are shifted for the wrist: 90+ normal, 86-89 watch,
    //! 85 and below act (and confirm with a fingertip oximeter).
    function spo2(v as Number) as [String, Number] {
        if (v <= 85) { return ["LOW", ALERT]; }
        if (v <= 89) { return ["BELOW", WARN]; }
        return ["NORM", GOOD];
    }

    //! Garmin recovery time in hours.
    function recovery(hours as Number) as [String, Number] {
        if (hours <= 0) { return ["READY", GOOD]; }
        if (hours <= 24) { return ["EASY", NORM]; }
        return ["REST", WARN];
    }

    //! Progress towards a goal: "64%" or "GOAL".
    function goal(value as Number, target as Number?) as [String, Number] {
        if (target == null || target <= 0) {
            return ["--", NONE];
        }
        var pct = value * 100 / target;
        if (pct >= 100) { return ["GOAL", GOOD]; }
        return [pct.format("%d") + "%", NORM];
    }

    //! Overnight Body Battery charge: how well the night restored energy.
    function charge(delta as Number) as [String, Number] {
        var text = "+" + delta.format("%d");
        if (delta >= 50) { return [text, GOOD]; }
        if (delta >= 25) { return [text, NORM]; }
        return [text, WARN];
    }

    //! Value relative to the user's own 7-day average: "92%".
    function relative(value as Number, average as Number?) as [String, Number] {
        if (average == null || average <= 0) {
            return ["--", NONE];
        }
        var pct = value * 100 / average;
        return [pct.format("%d") + "%", NORM];
    }
}
