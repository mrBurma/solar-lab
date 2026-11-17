import Toybox.Lang;

//! One metric slot as the renderer sees it: already formatted, no API calls.
class SlotModel {
    var kind as Number = -1;
    var label as String = "";
    var value as String = "--";
    var status as String = "NO DATA";
    var level as Number = Status.NONE;
    var fraction as Float? = null;           // fill of the micro scale, 0..1
    var ticks as Array<Float> = [] as Array<Float>;   // zone borders on the scale, 0..1
    var stale as Boolean = false;            // amber dot: old value
    var anomaly as Boolean = false;          // amber dot: off the personal norm
    var icon as String = "h";                // glyph in IconFont
    var meter as Float? = null;              // 0..1 fill drawn inside the icon (battery)

    function initialize() {
    }
}

//! Which four metrics are shown, and how each one is turned into a SlotModel.
//! The set follows the user's day (see phase()):
//!   MORNING  wake time .. + 3 h                    how did I recover?
//!   DAY      until the evening                     how am I now?
//!   EVENING  sunset - 2 h (not before 17:00) .. bed how was the day?
//!   NIGHT    sleep window                          sleep
module Slots {

    enum {
        BODY = 0,
        STRESS = 1,
        HR = 2,
        RHR = 3,
        RESP = 4,
        SPO2 = 5,
        RECOV = 6,
        STEPS = 7,
        INTENS = 8,
        KCAL = 9
    }

    enum {
        MORNING = 0,
        DAY = 1,
        EVENING = 2,
        NIGHT = 3
    }

    // Always the same four health signals in the same places, so each icon is
    // found without looking: heart, energy, stress, oxygen. Only the heart
    // changes meaning in the morning (resting HR against the norm). Activity
    // counters (steps, calories) are not health state and stay off the face;
    // the advice line covers "move" and "rest".
    const PRESETS = [
        [RHR, BODY, STRESS, SPO2],         // morning
        [HR, BODY, STRESS, SPO2],          // day
        [HR, BODY, STRESS, SPO2],          // evening
        [HR, BODY, STRESS, SPO2]           // night
    ] as Array<Array<Number>>;

    // Pictogram per kind (IconFont): BODY battery, STRESS face (changes with the
    // level), HR heart, RHR heart outline, RESP lungs, SPO2 "O2", RECOV hourglass, STEPS feet,
    // INTENS bolt, KCAL flame
    const ICONS = ["b", "2", "h", "H", "l", "o", "r", "f", "i", "k"] as Array<String>;

    // Zone borders drawn as notches on the micro scales
    const TICKS_QUARTERS = [0.25, 0.5, 0.75] as Array<Float>;
    const TICKS_HALF = [0.5] as Array<Float>;
    const TICKS_NONE = [] as Array<Float>;

    //! Phase of the day. Night is the user's sleep window (Garmin Connect bedtime
    //! and wake time, from 30 minutes before bedtime), not astronomical night:
    //! in a Moscow November it is dark at 17:00, which is not bedtime.
    //! Morning: wake time + 3 h. Evening: from 2 h before sunset, never before
    //! 17:00 (winter), until the sleep window. Day: the rest.
    function phase(solar as SolarState, minuteOfDay as Number, sleepMin as Number,
                   wakeMin as Number) as Number {
        var start = (sleepMin - 30 + 1440) % 1440;
        var inSleep = (start > wakeMin)
            ? (minuteOfDay >= start || minuteOfDay < wakeMin)
            : (minuteOfDay >= start && minuteOfDay < wakeMin);
        if (inSleep) {
            return NIGHT;
        }
        if (minuteOfDay >= wakeMin && minuteOfDay < wakeMin + 180) {
            return MORNING;
        }
        var set = solar.setMin;
        var evening = (set != null) ? (set as Float).toNumber() - 120 : 18 * 60;
        if (evening < 17 * 60) {
            evening = 17 * 60;
        }
        if (minuteOfDay >= evening) {
            return EVENING;
        }
        return DAY;
    }

    function preset(phase as Number) as Array<Number> {
        return PRESETS[phase];
    }

    //! Fills slot for kind from current data. All formatting happens here,
    //! once per minute, so drawing allocates nothing.
    function fill(slot as SlotModel, kind as Number, h as HealthData, b as Baseline,
                  phase as Number) as Void {
        slot.kind = kind;
        slot.value = "--";
        slot.status = "NO DATA";
        slot.level = Status.NONE;
        slot.fraction = null;
        slot.ticks = TICKS_NONE;
        slot.stale = false;
        slot.anomaly = false;
        slot.meter = null;
        slot.icon = ICONS[kind];

        if (kind == BODY) {
            slot.label = "ЭНЕРГИЯ";
            slot.ticks = TICKS_QUARTERS;
            var v = h.bb;
            if (v != null) {
                setValue(slot, v.format("%d"), v / 100.0, h.bbStale);
                slot.meter = (v < 0 ? 0 : (v > 100 ? 100 : v)) / 100.0;
                var st = Status.bodyBattery(v);
                // In the morning the overnight charge says more than the band
                if (phase == MORNING && h.charge != null) {
                    st = Status.charge(h.charge as Number);
                    slot.anomaly = b.isAnomaly(Baseline.CHARGE, h.charge);
                }
                setStatus(slot, st);
            }
        } else if (kind == STRESS) {
            slot.label = "СТРЕСС";
            slot.ticks = TICKS_QUARTERS;
            var v = h.stress;
            if (v != null) {
                setValue(slot, v.format("%d"), v / 100.0, h.stressStale);
                setStatus(slot, Status.stress(v));
                // The face itself says it: calm, neutral, tense
                slot.icon = (v <= 25) ? "1" : ((v <= 50) ? "2" : "3");
                slot.anomaly = b.isAnomaly(Baseline.STRESS, h.stressAvg);
            }
        } else if (kind == HR) {
            slot.label = "ПУЛЬС";
            var v = h.hr;
            var zones = h.zones;
            var top = (zones != null && zones.size() >= 6) ? zones[5] : 190;
            slot.ticks = hrTicks(h.rhrToday(), zones, top);
            if (v != null) {
                setValue(slot, v.format("%d"), (v - 40) / (top - 40.0), h.hrStale);
                setStatus(slot, Status.heartRate(v, h.rhrToday(), zones));
            }
        } else if (kind == RHR) {
            slot.label = "ПУЛЬС";        // outline heart = resting value
            var v = h.rhrToday();
            if (v != null) {
                setValue(slot, v.format("%d"), (v - 35) / 50.0, false);
                var delta = Readiness.rhrDelta(h, b);
                if (delta != null) {
                    setStatus(slot, Status.restingDelta(delta));
                } else {
                    setStatus(slot, ["REST", Status.NORM]);
                }
                slot.anomaly = b.isAnomaly(Baseline.RHR, h.nightRhr);
            }
        } else if (kind == RESP) {
            slot.label = "ДЫХАНИЕ";
            slot.ticks = [9.0 / 30.0, 20.0 / 30.0] as Array<Float>;
            var v = h.resp;
            if (v != null) {
                setValue(slot, v.format("%d"), v / 30.0, false);
                setStatus(slot, Status.respiration(v));
            }
        } else if (kind == SPO2) {
            slot.label = "КИСЛОРОД";
            slot.ticks = [0.3, 0.5] as Array<Float>;      // 86 % and 90 % on an 80..100 scale (wrist bands)
            var v = h.spo2;
            if (v == null) {
                v = h.spo2NightMin;
            }
            if (v != null) {
                setValue(slot, v.format("%d"), (v - 80) / 20.0, h.spo2 == null || h.spo2Stale);
                setStatus(slot, Status.spo2(v));
                slot.anomaly = b.isAnomaly(Baseline.SPO2, h.spo2NightMin);
            }
        } else if (kind == RECOV) {
            slot.label = "ВОССТ.";
            slot.ticks = [24.0 / 72.0] as Array<Float>;
            var m = h.recoveryMin;
            if (m != null) {
                var hours = (m + 59) / 60;
                setValue(slot, hours.format("%d") + "h", hours / 72.0, false);
                setStatus(slot, Status.recovery(hours));
            }
        } else if (kind == STEPS) {
            slot.label = "ШАГИ";
            slot.ticks = TICKS_HALF;
            var v = h.steps;
            if (v != null) {
                var goal = h.stepGoal;
                // 12480 -> "12.5k" so five digits fit the wider value font
                var text = (v >= 10000) ? (v / 1000.0).format("%.1f") + "k" : v.format("%d");
                setValue(slot, text, (goal != null && goal > 0) ? v.toFloat() / goal : null, false);
                setStatus(slot, Status.goal(v, goal));
            }
        } else if (kind == INTENS) {
            slot.label = "НАГРУЗКА";
            slot.ticks = TICKS_HALF;
            var v = h.intensity;
            if (v != null) {
                var goal = h.intensityGoal;
                setValue(slot, v.format("%d"), (goal != null && goal > 0) ? v.toFloat() / goal : null, false);
                setStatus(slot, Status.goal(v, goal));
            }
        } else if (kind == KCAL) {
            slot.label = "ККАЛ";
            slot.ticks = TICKS_HALF;
            var v = h.kcal;
            if (v != null) {
                var avg = h.kcalAverage;
                // Scale: today against twice the personal daily average
                setValue(slot, v.format("%d"), (avg != null && avg > 0) ? v / (2.0 * avg) : null, false);
                var st = Status.relative(v, avg);
                slot.status = (avg != null) ? st[0] + " AVG" : st[0];
                slot.level = st[1];
            }
        }
    }

    function setValue(slot as SlotModel, text as String, fraction as Numeric?, stale as Boolean) as Void {
        slot.value = text;
        slot.stale = stale;
        if (fraction != null) {
            var f = fraction.toFloat();
            if (f < 0.0) { f = 0.0; }
            if (f > 1.0) { f = 1.0; }
            slot.fraction = f;
        }
    }

    function setStatus(slot as SlotModel, st as [String, Number]) as Void {
        slot.status = st[0];
        slot.level = st[1];
    }

    //! Heart-rate scale 40..top with notches at rest + 10, zone 1 top, zone 3 top.
    function hrTicks(rhr as Number?, zones as Array<Number>?, top as Number) as Array<Float> {
        var span = top - 40.0;
        var restTop = (rhr != null) ? rhr + 10 : 70;
        var a = 110;
        var c = 150;
        if (zones != null && zones.size() >= 6) {
            a = zones[1];
            c = zones[3];
        }
        return [(restTop - 40) / span, (a - 40) / span, (c - 40) / span] as Array<Float>;
    }
}
