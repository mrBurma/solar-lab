import Toybox.ActivityMonitor;
import Toybox.Complications;
import Toybox.Lang;
import Toybox.SensorHistory;
import Toybox.System;
import Toybox.Time;
import Toybox.UserProfile;

//! Body Battery state of a 15-minute bucket on the 24 h balance ring
//! (activity is kept separately in HealthData.ringActive).
module RingState {
    const NONE = 0;       // no data
    const DRAIN = 1;      // ordinary time, Body Battery not rising
    const CHARGE = 2;     // Body Battery rose: sleep, calm rest
}

//! Data acquisition and validation for all health metrics.
//!
//! Sources, in order of preference for every "current" value:
//!   1. Complications (system values, the freshest the face can read);
//!   2. the newest SensorHistory / ActivityMonitor sample, marked STALE when old;
//!   3. nothing: the value stays null and is drawn as "--".
//! No value is ever invented. Derived values are computed here from history:
//!   - overnight Body Battery charge (minimum during the night -> maximum after it);
//!   - pressure tendency corrected for altitude changes;
//!   - night resting HR as the lowest 30-minute mean, Garmin's own definition;
//!   - night SpO2 minimum; average daytime stress;
//!   - the 24-hour Body Battery trace for the perimeter ring;
//!   - 7-day calorie average from ActivityMonitor daily history.
//! Heavy history scans run as jobs, at most one per onUpdate, so a single frame
//! never comes near the watchdog limit.
class HealthData {

    // Staleness limits, seconds
    const HR_STALE = 300;
    const BB_STALE = 1800;
    const MAX_AGE = 3 * 3600;     // older samples are treated as no data

    // Ring: 96 buckets of 15 minutes, indexed by local time of day
    const RING_BUCKETS = 96;

    // Heavy jobs (bit flags)
    enum {
        JOB_RING = 1,
        JOB_STRESS = 2,
        JOB_PRESSURE = 4,
        JOB_DAILY = 8,
        JOB_NIGHT_BB = 16,
        JOB_NIGHT_HR = 32,
        JOB_NIGHT_SPO2 = 64,
        JOB_NIGHT_STRESS = 128,
        JOB_ACTIVITY = 256
    }

    // ---- current values (null = no data)
    var bb as Number? = null;
    var bbStale as Boolean = false;
    var stress as Number? = null;
    var stressStale as Boolean = false;
    var hr as Number? = null;
    var hrStale as Boolean = false;
    var resp as Number? = null;
    var spo2 as Number? = null;
    var spo2Stale as Boolean = false;     // newest reading older than 4 h (the complication has no time)
    var recoveryMin as Number? = null;
    var steps as Number? = null;
    var stepGoal as Number? = null;
    var kcal as Number? = null;
    var intensity as Number? = null;      // weekly intensity minutes
    var intensityGoal as Number? = null;
    var moveLevel as Number? = null;      // 0..5, inactivity bar
    var movedAt as Number = 0;            // last time >= 150 steps within ~5 min
    private var _stepsHist as Array<Number> = [-1, -1, -1, -1, -1, -1] as Array<Number>;
    private var _stepsIdx as Number = 0;
    private var _stepsMinute as Number = -1;
    var pressurePa as Float? = null;      // sea level pressure

    // ---- profile
    var rhrProfile as Number? = null;     // resting HR reported by the system
    var rhrAverage as Number? = null;     // Garmin's historical average of resting HR
    var zones as Array<Number>? = null;

    // ---- derived values
    var nightRhr as Number? = null;       // lowest 30-minute HR mean last night
    var charge as Number? = null;         // overnight Body Battery charge
    var spo2NightMin as Number? = null;
    var stressAvg as Number? = null;      // average stress since wake-up today
    var stressAvgYesterday as Number? = null;
    var pressureTrend as Float? = null;   // hPa per 3 hours
    var kcalAverage as Number? = null;    // 7-day daily average
    var ring as Array<Number>;            // Body Battery per 15 min, -1 = no data
    var ringState as Array<Number>;       // per 15 min: RingState.NONE / DRAIN / CHARGE
    var ringActive as Array<Boolean>;     // per 15 min: heart rate in the moderate zone or above
    var ringReady as Boolean = false;

    // ---- night window of the current day, UTC seconds
    var sleepStart as Number = 0;
    var wakeEnd as Number = 0;
    var sleepMinute as Number = 23 * 60;  // typical bedtime, local minutes after midnight
    var wakeMinute as Number = 7 * 60;    // typical wake time

    private var _jobs as Number = 0;
    private var _lastSlowRefresh as Number = -9999;
    private var _nightDay as Number = -1;
    private var _dailyDay as Number = -1;

    private var _idBB as Complications.Id?;
    private var _idStress as Complications.Id?;
    private var _idHR as Complications.Id?;
    private var _idResp as Complications.Id?;
    private var _idSpo2 as Complications.Id?;
    private var _idRecov as Complications.Id?;
    private var _idPressure as Complications.Id?;

    function initialize() {
        ring = new Array<Number>[RING_BUCKETS];
        ringState = new Array<Number>[RING_BUCKETS];
        ringActive = new Array<Boolean>[RING_BUCKETS];
        for (var i = 0; i < RING_BUCKETS; i++) {
            ringState[i] = RingState.NONE;
            ringActive[i] = false;
            ring[i] = -1;
        }
        if (Toybox has :Complications) {
            _idBB = new Complications.Id(Complications.COMPLICATION_TYPE_BODY_BATTERY);
            _idStress = new Complications.Id(Complications.COMPLICATION_TYPE_STRESS);
            _idHR = new Complications.Id(Complications.COMPLICATION_TYPE_HEART_RATE);
            _idResp = new Complications.Id(Complications.COMPLICATION_TYPE_RESPIRATION_RATE);
            _idSpo2 = new Complications.Id(Complications.COMPLICATION_TYPE_PULSE_OX);
            _idRecov = new Complications.Id(Complications.COMPLICATION_TYPE_RECOVERY_TIME);
            _idPressure = new Complications.Id(Complications.COMPLICATION_TYPE_SEA_LEVEL_PRESSURE);
        }
    }

    // ================================================================ refresh

    //! Cheap refresh of current values. Call once per minute and on wake-up.
    function refresh(now as Number, tz as Number) as Void {
        readHeartRate(now);
        readBodyBattery(now);
        readStress(now);
        resp = compNumber(_idResp);
        spo2 = compNumber(_idSpo2);
        readSpo2Age(now);
        recoveryMin = compNumber(_idRecov);
        // Sea-level pressure; values outside 870..1090 hPa are sensor or simulator noise
        var p = compNumber(_idPressure);
        pressurePa = (p != null && p >= 87000 && p <= 109000) ? p.toFloat() : null;

        var info = ActivityMonitor.getInfo();
        steps = info.steps;
        stepGoal = info.stepGoal;
        kcal = info.calories;
        moveLevel = info.moveBarLevel;
        trackMovement(now);
        intensityGoal = info.activeMinutesWeekGoal;
        var week = info.activeMinutesWeek;
        intensity = (week != null) ? week.total : null;
        if (resp == null) {
            resp = info.respirationRate;
        }
        if (recoveryMin == null) {
            var hours = info.timeToRecovery;
            recoveryMin = (hours != null) ? hours * 60 : null;
        }

        readProfile();
        updateNightWindow(now, tz);

        // History jobs: every 15 minutes, night and daily jobs once per day
        if (now - _lastSlowRefresh >= 900) {
            _lastSlowRefresh = now;
            _jobs |= JOB_RING | JOB_ACTIVITY | JOB_STRESS | JOB_PRESSURE;
        }
        var day = (now + tz) / 86400;
        if (_nightDay != day && now >= wakeEnd + 1800) {
            _nightDay = day;
            _jobs |= JOB_NIGHT_BB | JOB_NIGHT_HR | JOB_NIGHT_SPO2 | JOB_NIGHT_STRESS;
        }
        if (_dailyDay != day) {
            _jobs |= JOB_DAILY;
        }
    }

    //! Own movement detection, independent of Garmin's move bar (which on the
    //! watch was seen to stay on after a walk): one step count per minute is kept
    //! for 5 minutes; 150+ steps in that window counts as having moved.
    private function trackMovement(now as Number) as Void {
        var s = steps;
        if (s == null) {
            return;
        }
        var minute = now / 60;
        if (minute != _stepsMinute) {
            _stepsMinute = minute;
            _stepsIdx = (_stepsIdx + 1) % _stepsHist.size();
            _stepsHist[_stepsIdx] = s;
        }
        var oldest = s;
        for (var i = 0; i < _stepsHist.size(); i++) {
            var v = _stepsHist[i];
            if (v >= 0 && v < oldest) {
                oldest = v;        // midnight reset gives a larger old value: ignored
            }
        }
        if (s - oldest >= 150) {
            movedAt = now;
        }
    }

    //! Heart rate only, for the 1 Hz high-power period.
    function refreshHeartRate(now as Number) as Void {
        readHeartRate(now);
    }

    //! Runs at most one pending history job. Returns true if a job ran.
    function runJob(now as Number, tz as Number, baseline as Baseline) as Boolean {
        if (_jobs == 0) {
            return false;
        }
        if ((_jobs & JOB_RING) != 0) {
            _jobs &= ~JOB_RING;
            computeRing(now, tz);
        } else if ((_jobs & JOB_ACTIVITY) != 0) {
            _jobs &= ~JOB_ACTIVITY;
            computeActivity(now, tz);
        } else if ((_jobs & JOB_STRESS) != 0) {
            _jobs &= ~JOB_STRESS;
            stressAvg = averageStress(wakeEnd, now);
        } else if ((_jobs & JOB_PRESSURE) != 0) {
            _jobs &= ~JOB_PRESSURE;
            computePressureTrend();
        } else if ((_jobs & JOB_NIGHT_BB) != 0) {
            _jobs &= ~JOB_NIGHT_BB;
            charge = nightCharge(now);
        } else if ((_jobs & JOB_NIGHT_HR) != 0) {
            _jobs &= ~JOB_NIGHT_HR;
            nightRhr = nightRestingHr(now);
        } else if ((_jobs & JOB_NIGHT_SPO2) != 0) {
            _jobs &= ~JOB_NIGHT_SPO2;
            spo2NightMin = nightSpo2Min(now);
        } else if ((_jobs & JOB_NIGHT_STRESS) != 0) {
            // Last night job: yesterday's daytime stress, then one baseline record
            _jobs &= ~JOB_NIGHT_STRESS;
            stressAvgYesterday = averageStress(wakeEnd - 86400, sleepStart);
            baseline.store((now + tz) / 86400, charge, stressAvgYesterday, spo2NightMin, nightRhr);
        } else if ((_jobs & JOB_DAILY) != 0) {
            _jobs &= ~JOB_DAILY;
            computeDailyAverages();
            _dailyDay = (now + tz) / 86400;
        }
        return true;
    }

    //! Today's resting HR: our night estimate, else the system value.
    function rhrToday() as Number? {
        return (nightRhr != null) ? nightRhr : rhrProfile;
    }

    //! Complication used to open the native widget for a slot kind.
    function complicationFor(kind as Number) as Complications.Id? {
        if (kind == Slots.BODY) { return _idBB; }
        if (kind == Slots.STRESS) { return _idStress; }
        if (kind == Slots.HR || kind == Slots.RHR) { return _idHR; }
        if (kind == Slots.RESP) { return _idResp; }
        if (kind == Slots.SPO2) { return _idSpo2; }
        if (kind == Slots.RECOV) { return _idRecov; }
        if (!(Toybox has :Complications)) { return null; }
        if (kind == Slots.STEPS) { return new Complications.Id(Complications.COMPLICATION_TYPE_STEPS); }
        if (kind == Slots.KCAL) { return new Complications.Id(Complications.COMPLICATION_TYPE_CALORIES); }
        if (kind == Slots.INTENS) { return new Complications.Id(Complications.COMPLICATION_TYPE_INTENSITY_MINUTES); }
        return null;
    }

    // ============================================================ current values

    private function readHeartRate(now as Number) as Void {
        var v = compNumber(_idHR);
        if (v != null && v > 0) {
            hr = v;
            hrStale = false;
            return;
        }
        // Off the wrist or no live value: the newest stored sample
        hr = null;
        hrStale = false;
        var it = ActivityMonitor.getHeartRateHistory(1, true);
        var s = it.next();
        if (s != null && s.heartRate != ActivityMonitor.INVALID_HR_SAMPLE && s.when != null) {
            var age = now - (s.when as Time.Moment).value();
            if (age <= MAX_AGE) {
                hr = s.heartRate;
                hrStale = age > HR_STALE;
            }
        }
    }

    private function readBodyBattery(now as Number) as Void {
        var v = compNumber(_idBB);
        if (v != null) {
            bb = v;
            bbStale = false;
            return;
        }
        var s = newestSample(:getBodyBatteryHistory);
        bb = null;
        bbStale = false;
        if (s != null && s.data != null) {
            var age = now - s.when.value();
            if (age <= MAX_AGE) {
                bb = (s.data as Numeric).toNumber();
                bbStale = age > BB_STALE;
            }
        }
    }

    //! Stress is not measured during movement: the system then returns null.
    private function readStress(now as Number) as Void {
        var v = compNumber(_idStress);
        if (v != null && v >= 0) {
            stress = v;
            stressStale = false;
            return;
        }
        var s = newestSample(:getStressHistory);
        stress = null;
        stressStale = false;
        if (s != null && s.data != null) {
            var age = now - s.when.value();
            if (age <= MAX_AGE) {
                stress = (s.data as Numeric).toNumber();
                stressStale = age > BB_STALE;
            }
        }
    }

    private function readProfile() as Void {
        var profile = UserProfile.getProfile();
        rhrProfile = profile.restingHeartRate;
        rhrAverage = profile.averageRestingHeartRate;
        if (zones == null) {
            zones = UserProfile.getHeartRateZones(UserProfile.HR_ZONE_SPORT_GENERIC);
        }
    }

    //! Night window from the typical sleep and wake times in the user profile
    //! (defaults 23:00 and 07:00). wakeEnd is today's wake time; before it, the
    //! window of the night in progress.
    private function updateNightWindow(now as Number, tz as Number) as Void {
        var profile = UserProfile.getProfile();
        var sleepT = profile.sleepTime;
        var wakeT = profile.wakeTime;
        var sleepS = (sleepT != null) ? sleepT.value() : 23 * 3600;
        var wakeS = (wakeT != null) ? wakeT.value() : 7 * 3600;
        sleepMinute = (sleepS / 60) % 1440;
        wakeMinute = (wakeS / 60) % 1440;
        var duration = ((wakeS - sleepS) % 86400 + 86400) % 86400;
        if (duration < 3 * 3600) {
            duration = 8 * 3600;
        }
        var dayStart = ((now + tz) / 86400) * 86400 - tz;   // local midnight, UTC seconds
        wakeEnd = dayStart + wakeS;
        sleepStart = wakeEnd - duration;
    }

    // ================================================================= history

    //! The 24 h balance ring, part 1: Body Battery per 15-minute bucket (local
    //! time of day) and charge / drain. "Charge" is a rise against the previous
    //! bucket with data. Activity is a separate job (computeActivity) so no
    //! single frame walks both 23-hour histories.
    private function computeRing(now as Number, tz as Number) as Void {
        for (var i = 0; i < RING_BUCKETS; i++) {
            ring[i] = -1;
            ringState[i] = RingState.NONE;
        }
        var oldest = now - 23 * 3600;    // keep a visible gap after "now"
        var any = false;
        var it = history(:getBodyBatteryHistory, 86400);
        if (it != null) {
            var s = it.next();
            while (s != null) {
                var t = s.when.value();
                if (s.data != null && t >= oldest) {
                    ring[bucketOf(t, tz)] = (s.data as Numeric).toNumber();
                    any = true;
                }
                s = it.next();
            }
        }

        // Charge / drain, walking the buckets in time order from the oldest.
        // Body Battery moves in whole steps and is sampled sparsely: in a quiet
        // night it may gain 1 point per 30-45 minutes, so comparing neighbouring
        // 15-minute buckets would mark every other one as "drain" and tear the
        // ring. A bucket is "charge" when it is above the value about an hour
        // earlier (the oldest sample within the previous 4 buckets).
        var first = bucketOf(oldest, tz);
        for (var k = 0; k <= 92; k++) {          // 93 buckets, the last one holds "now"
            var b = (first + k) % RING_BUCKETS;
            var v = ring[b];
            if (v < 0) {
                continue;
            }
            var ref = -1;
            for (var j = (k >= 4 ? k - 4 : 0); j < k && ref < 0; j++) {
                ref = ring[(first + j) % RING_BUCKETS];
            }
            ringState[b] = (ref >= 0 && v > ref) ? RingState.CHARGE : RingState.DRAIN;
        }
        // Up to two buckets without a sample between charging ones are charging
        // too (a longer hole, e.g. the watch off the wrist, stays empty)
        for (var k = 1; k < 92; k++) {
            var b = (first + k) % RING_BUCKETS;
            if (ringState[b] != RingState.NONE
                    || ringState[(first + k - 1) % RING_BUCKETS] != RingState.CHARGE) {
                continue;
            }
            var n1 = ringState[(first + k + 1) % RING_BUCKETS];
            var n2 = (k + 2 <= 92) ? ringState[(first + k + 2) % RING_BUCKETS] : RingState.NONE;
            if (n1 == RingState.CHARGE || (n1 == RingState.NONE && n2 == RingState.CHARGE)) {
                ringState[b] = RingState.CHARGE;
            }
        }

        ringReady = any;
    }

    //! The 24 h balance ring, part 2: active buckets. Connect IQ gives no hourly
    //! intensity minutes, so activity is derived the way Garmin counts them: heart
    //! rate at or above the start of zone 2 in at least a third of the bucket's
    //! samples (and at least two of them).
    private function computeActivity(now as Number, tz as Number) as Void {
        var z = zones;
        var rest = rhrToday();
        var limit = (z != null && z.size() >= 2) ? z[1] : ((rest != null) ? rest + 45 : 110);
        var oldest = now - 23 * 3600;
        // Per bucket: samples at or above the limit * 1000 + all samples
        var counts = new Array<Number>[RING_BUCKETS];
        for (var i = 0; i < RING_BUCKETS; i++) {
            counts[i] = 0;
        }
        var it = history(:getHeartRateHistory, 23 * 3600);
        if (it != null) {
            var s = it.next();
            while (s != null) {
                var t = s.when.value();
                if (s.data != null && t >= oldest) {
                    var v = (s.data as Numeric).toNumber();
                    if (v > 25 && v < 230) {
                        counts[bucketOf(t, tz)] += (v >= limit) ? 1001 : 1;
                    }
                }
                s = it.next();
            }
        }
        for (var i = 0; i < RING_BUCKETS; i++) {
            var above = counts[i] / 1000;
            var total = counts[i] % 1000;
            ringActive[i] = (total > 0 && above >= 2 && above * 3 >= total);
            if (total > 0 && ringState[i] == RingState.NONE) {
                ringState[i] = RingState.DRAIN;   // heart rate seen, no Body Battery
            }
        }
    }

    //! Local 15-minute bucket (0..95) of a UTC moment.
    private function bucketOf(t as Number, tz as Number) as Number {
        return (((t + tz) % 86400 + 86400) % 86400) / 900;
    }

    //! Age of the blood-oxygen value. The Pulse Ox complication carries no time,
    //! so the newest SensorHistory sample tells how old the reading is. A sample
    //! from the last hour also replaces the complication value.
    private function readSpo2Age(now as Number) as Void {
        spo2Stale = false;
        var s = newestSample(:getOxygenSaturationHistory);
        if (s == null || s.data == null) {
            return;
        }
        var age = now - s.when.value();
        if (spo2 == null || age <= 3600) {
            spo2 = (s.data as Numeric).toNumber();
        }
        spo2Stale = age > 4 * 3600;
    }

    //! Mean stress between two moments, ignoring samples without a value.
    private function averageStress(from as Number, to as Number) as Number? {
        if (to <= from) {
            return null;
        }
        var now = Time.now().value();
        var it = history(:getStressHistory, now - from);
        if (it == null) {
            return null;
        }
        var sum = 0;
        var n = 0;
        var s = it.next();
        while (s != null) {
            var t = s.when.value();
            if (t >= from && t <= to && s.data != null) {
                var v = (s.data as Numeric).toNumber();
                if (v >= 0) {
                    sum += v;
                    n += 1;
                }
            }
            s = it.next();
        }
        return (n >= 6) ? sum / n : null;
    }

    //! 3-hour weather pressure tendency in hPa.
    //! The barometer measures station pressure, which also changes when the user
    //! changes altitude (about 0.12 hPa per metre near sea level). The elevation
    //! change over the same window is added back, so a climb or an elevator ride is
    //! not shown as a falling barometer:  dP_weather = dP_station + 0.12 * dh.
    //! Values beyond +-15 hPa / 3 h are physically implausible and are dropped.
    private function computePressureTrend() as Void {
        pressureTrend = null;
        var p = firstLast(:getPressureHistory, 3 * 3600);
        if (p == null) {
            return;
        }
        var span = p[3] - p[2];
        if (span < 3600) {
            return;
        }
        var delta = (p[1] - p[0]) / 100.0;
        var e = firstLast(:getElevationHistory, 3 * 3600);
        if (e != null) {
            delta += 0.12 * (e[1] - e[0]);
        }
        var trend = (delta * 10800.0 / span).toFloat();
        if (trend.abs() <= 15.0) {
            pressureTrend = trend;
        }
    }

    //! [first value, last value, first time, last time] of a history, or null.
    private function firstLast(kind as Symbol, seconds as Number) as [Float, Float, Number, Number]? {
        var it = history(kind, seconds);
        if (it == null) {
            return null;
        }
        var first = null as SensorHistory.SensorSample?;
        var last = null as SensorHistory.SensorSample?;
        var s = it.next();
        while (s != null) {
            if (s.data != null) {
                if (first == null) {
                    first = s;
                }
                last = s;
            }
            s = it.next();
        }
        if (first == null || last == null) {
            return null;
        }
        return [(first.data as Numeric).toFloat(), (last.data as Numeric).toFloat(),
                first.when.value(), last.when.value()];
    }

    //! Overnight Body Battery charge: lowest value in the night window (one hour
    //! margin on both sides), then the highest value after it until 2 h after wake.
    private function nightCharge(now as Number) as Number? {
        var it = history(:getBodyBatteryHistory, now - (sleepStart - 3600));
        if (it == null) {
            return null;
        }
        var minV = 101;
        var maxAfter = -1;
        var s = it.next();
        while (s != null) {
            var t = s.when.value();
            if (s.data != null && t >= sleepStart - 3600 && t <= wakeEnd + 7200) {
                var v = (s.data as Numeric).toNumber();
                if (t <= wakeEnd + 3600 && v < minV) {
                    minV = v;
                    maxAfter = v;
                } else if (v > maxAfter) {
                    maxAfter = v;
                }
            }
            s = it.next();
        }
        return (minV <= 100 && maxAfter >= minV) ? maxAfter - minV : null;
    }

    //! Resting HR as Garmin defines it: the lowest 30-minute mean. HR samples of
    //! the night go into 5-minute bins; the lowest mean of 6 consecutive bins
    //! that all have data is the result.
    private function nightRestingHr(now as Number) as Number? {
        var bins = (wakeEnd - sleepStart) / 300;
        if (bins < 6 || bins > 200) {
            return null;
        }
        var it = history(:getHeartRateHistory, now - sleepStart);
        if (it == null) {
            return null;
        }
        var sums = new Array<Number>[bins];
        var counts = new Array<Number>[bins];
        for (var i = 0; i < bins; i++) {
            sums[i] = 0;
            counts[i] = 0;
        }
        var s = it.next();
        while (s != null) {
            var t = s.when.value();
            if (s.data != null && t >= sleepStart && t < wakeEnd) {
                var v = (s.data as Numeric).toNumber();
                if (v > 25 && v < 220) {
                    var b = (t - sleepStart) / 300;
                    sums[b] += v;
                    counts[b] += 1;
                }
            }
            s = it.next();
        }
        var best = 999.0;
        for (var i = 0; i + 6 <= bins; i++) {
            var sum = 0.0;
            var ok = true;
            for (var j = i; j < i + 6; j++) {
                if (counts[j] == 0) {
                    ok = false;
                    break;
                }
                sum += sums[j].toFloat() / counts[j];
            }
            if (ok && sum / 6.0 < best) {
                best = sum / 6.0;
            }
        }
        return (best < 999.0) ? (best + 0.5).toNumber() : null;
    }

    //! Lowest SpO2 reading of the night (only exists with sleep Pulse Ox enabled).
    private function nightSpo2Min(now as Number) as Number? {
        var it = history(:getOxygenSaturationHistory, now - sleepStart);
        if (it == null) {
            return null;
        }
        var minS = 101;
        var s = it.next();
        while (s != null) {
            var t = s.when.value();
            if (s.data != null && t >= sleepStart && t <= wakeEnd) {
                var v = (s.data as Numeric).toNumber();
                if (v >= 50 && v < minS) {
                    minS = v;
                }
            }
            s = it.next();
        }
        return (minS <= 100) ? minS : null;
    }

    //! 7-day calorie average from ActivityMonitor daily history.
    private function computeDailyAverages() as Void {
        kcalAverage = null;
        var days = ActivityMonitor.getHistory();
        var sum = 0;
        var n = 0;
        for (var i = 0; i < days.size(); i++) {
            var c = days[i].calories;
            if (c != null && c > 0) {
                sum += c;
                n += 1;
            }
        }
        if (n >= 3) {
            kcalAverage = sum / n;
        }
    }

    // ================================================================= helpers

    //! Numeric value of a system complication, or null.
    private function compNumber(id as Complications.Id?) as Number? {
        if (id == null) {
            return null;
        }
        try {
            var v = Complications.getComplication(id).value;
            if (v instanceof Number || v instanceof Float || v instanceof Long || v instanceof Double) {
                return v.toNumber();
            }
        } catch (e) {
            // Complication not available on this device or right now
        }
        return null;
    }

    //! SensorHistory iterator for the last `seconds`, oldest sample first.
    private function history(kind as Symbol, seconds as Number) as SensorHistory.SensorHistoryIterator? {
        if (!(Toybox has :SensorHistory) || seconds <= 0) {
            return null;
        }
        var options = {
            :period => new Time.Duration(seconds),
            :order => SensorHistory.ORDER_OLDEST_FIRST
        };
        if (kind == :getBodyBatteryHistory && (SensorHistory has :getBodyBatteryHistory)) {
            return SensorHistory.getBodyBatteryHistory(options);
        }
        if (kind == :getStressHistory && (SensorHistory has :getStressHistory)) {
            return SensorHistory.getStressHistory(options);
        }
        if (kind == :getHeartRateHistory && (SensorHistory has :getHeartRateHistory)) {
            return SensorHistory.getHeartRateHistory(options);
        }
        if (kind == :getOxygenSaturationHistory && (SensorHistory has :getOxygenSaturationHistory)) {
            return SensorHistory.getOxygenSaturationHistory(options);
        }
        if (kind == :getPressureHistory && (SensorHistory has :getPressureHistory)) {
            return SensorHistory.getPressureHistory(options);
        }
        if (kind == :getElevationHistory && (SensorHistory has :getElevationHistory)) {
            return SensorHistory.getElevationHistory(options);
        }
        return null;
    }

    //! The newest sample of a history, or null.
    private function newestSample(kind as Symbol) as SensorHistory.SensorSample? {
        if (!(Toybox has :SensorHistory)) {
            return null;
        }
        var options = { :period => 1, :order => SensorHistory.ORDER_NEWEST_FIRST };
        var it = null;
        if (kind == :getBodyBatteryHistory && (SensorHistory has :getBodyBatteryHistory)) {
            it = SensorHistory.getBodyBatteryHistory(options);
        } else if (kind == :getStressHistory && (SensorHistory has :getStressHistory)) {
            it = SensorHistory.getStressHistory(options);
        } else if (kind == :getOxygenSaturationHistory && (SensorHistory has :getOxygenSaturationHistory)) {
            it = SensorHistory.getOxygenSaturationHistory(options);
        }
        return (it != null) ? it.next() : null;
    }
}
