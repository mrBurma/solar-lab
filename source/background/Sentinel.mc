import Toybox.Activity;
import Toybox.ActivityMonitor;
import Toybox.Application;
import Toybox.Background;
import Toybox.Lang;
import Toybox.Notifications;
import Toybox.SensorHistory;
import Toybox.System;
import Toybox.Time;
import Toybox.UserProfile;
import Toybox.Weather;

//! Background sentinel of the watch face. The system wakes it every 5 minutes
//! (the Connect IQ minimum), also while the screen is off. It looks at the last
//! minutes of sensor history and sends a system notification (with the watch's
//! normal notification vibration) when something needs attention outside a
//! recorded activity. During an activity the SOLAR·LAB Guard field takes over.
//!
//! Rules (each with its own cooldown, so a situation produces one notification):
//!   HR HIGH      10 min in zone 4+ while no activity is recorded; the text says
//!                why: climbing (floors), moving (steps) or at rest
//!   HR HIGH REST 10 min >= resting + 30 bpm (night: + 25) with almost no steps
//!   HR LOW       10 min <= 38 bpm
//!   SPO2 LOW     two readings <= 85 % within 30 min (wrist sensor reads low, indicative)
//!   STRESS       30 min of stress >= 76 in the day
//!   HEAT         air >= 30 deg C and 10 min in zone 3+
//! Limits of the platform: 5-10 minutes of latency; outside an activity the watch
//! stores heart rate only every 1-2 minutes; at night Sleep mode / Do Not Disturb
//! may silence the notification, so every event is also logged in Storage and
//! shown on the watch face (note line) for 12 hours.
(:background)
class Sentinel extends System.ServiceDelegate {

    const STATE_KEY = "sentinel";     // [steps, floors, time, last fire per rule x6]
    const LOG_KEY = "events";         // [[time, text], ...] newest last, max 5

    enum {
        R_HIGH = 0,
        R_REST = 1,
        R_LOW = 2,
        R_SPO2 = 3,
        R_STRESS = 4,
        R_HEAT = 5
    }

    const COOLDOWN = [1800, 3600, 3600, 7200, 7200, 3600] as Array<Number>;

    function initialize() {
        ServiceDelegate.initialize();
    }

    function onTemporalEvent() as Void {
        try {
            check();
        } catch (e) {
            // Never let a sensor or storage problem kill the background process
        }
        Background.exit(null);
    }

    private function check() as Void {
        var now = Time.now().value();
        var clock = System.getClockTime();
        var tz = clock.timeZoneOffset;

        // An activity is recorded: the Guard field is in charge
        var act = Activity.getActivityInfo();
        var recording = (act != null && act.timerState == Activity.TIMER_STATE_ON);

        // Movement since the previous run (about 5 minutes ago)
        var info = ActivityMonitor.getInfo();
        var steps = (info.steps != null) ? info.steps as Number : 0;
        var floors = (info.floorsClimbed != null) ? info.floorsClimbed as Number : 0;
        var state = loadState();
        var dtState = now - state[2];
        var dSteps = (dtState > 0 && dtState <= 900 && steps >= state[0]) ? steps - state[0] : -1;
        var dFloors = (dtState > 0 && dtState <= 900 && floors >= state[1]) ? floors - state[1] : 0;
        state[0] = steps;
        state[1] = floors;
        state[2] = now;

        // Profile: zones, resting HR, night window
        var zones = UserProfile.getHeartRateZones(UserProfile.HR_ZONE_SPORT_GENERIC);
        var z3 = 130;
        var z4 = 150;
        if (zones != null && zones.size() >= 6) {
            z3 = zones[2] + 1;
            z4 = zones[3] + 1;
        }
        var profile = UserProfile.getProfile();
        var rhr = (profile.restingHeartRate != null) ? profile.restingHeartRate as Number : 60;
        var night = isNight(profile, now, tz);

        // Heart rate over the last 10 minutes
        var hr = window(:hr, 600);           // [min, max, last, count, span]
        if (hr != null && hr[3] >= 4 && hr[4] >= 420) {
            var minHr = hr[0];
            var maxHr = hr[1];
            var last = hr[2];
            var still = (dSteps >= 0 && dSteps < 150);

            if (!recording && minHr >= z4) {
                var why = txt(Rez.Strings.SnAtRest);
                if (dFloors >= 3) {
                    why = Lang.format(txt(Rez.Strings.SnClimbing), [dFloors]);
                } else if (dSteps >= 400) {
                    why = txt(Rez.Strings.SnMoving);
                }
                fire(state, R_HIGH, now, Lang.format(txt(Rez.Strings.SnHighTitle), [last]), why);
            } else if (!recording && still && minHr >= rhr + (night ? 25 : 30) && minHr >= 90) {
                fire(state, R_REST, now, Lang.format(txt(Rez.Strings.SnRestTitle), [last]),
                    Lang.format(txt(Rez.Strings.SnRestBody), [rhr, minHr - rhr]));
            } else if (maxHr <= 38) {
                fire(state, R_LOW, now, Lang.format(txt(Rez.Strings.SnLowTitle), [last]), txt(Rez.Strings.SnLowBody));
            }

            // Heat: hot air and sustained effort
            if (!recording && minHr >= z3) {
                var w = Weather.getCurrentConditions();
                if (w != null && w.temperature != null && (w.temperature as Numeric) >= 30) {
                    fire(state, R_HEAT, now, Lang.format(txt(Rez.Strings.SnHeatTitle), [(w.temperature as Numeric).toNumber()]),
                        Lang.format(txt(Rez.Strings.SnHeatBody), [last]));
                }
            }
        }

        // Blood oxygen: two low readings within 30 minutes
        var ox = window(:spo2, 1800);
        if (ox != null && ox[5] >= 2) {
            fire(state, R_SPO2, now, Lang.format(txt(Rez.Strings.SnSpo2Title), [ox[0]]),
                txt(night ? Rez.Strings.SnSpo2Night : Rez.Strings.SnSpo2Day));
        }

        // Sustained stress in the day
        if (!night && !recording) {
            var st = window(:stress, 1800);
            if (st != null && st[3] >= 6 && st[0] >= 76) {
                fire(state, R_STRESS, now, txt(Rez.Strings.SnStressTitle), txt(Rez.Strings.SnStressBody));
            }
        }

        Application.Storage.setValue(STATE_KEY, state as Array<Application.Storage.ValueType>);
    }

    //! [min, max, last, count, span seconds, count <= 85] of a history over `seconds`.
    private function window(kind as Symbol, seconds as Number) as Array<Number>? {
        var options = { :period => new Time.Duration(seconds), :order => SensorHistory.ORDER_OLDEST_FIRST };
        var it = null;
        if (kind == :hr && (SensorHistory has :getHeartRateHistory)) {
            it = SensorHistory.getHeartRateHistory(options);
        } else if (kind == :spo2 && (SensorHistory has :getOxygenSaturationHistory)) {
            it = SensorHistory.getOxygenSaturationHistory(options);
        } else if (kind == :stress && (SensorHistory has :getStressHistory)) {
            it = SensorHistory.getStressHistory(options);
        }
        if (it == null) {
            return null;
        }
        var minV = 9999;
        var maxV = -1;
        var last = 0;
        var n = 0;
        var low = 0;
        var t0 = 0;
        var t1 = 0;
        var s = it.next();
        while (s != null) {
            if (s.data != null) {
                var v = (s.data as Numeric).toNumber();
                var valid = (kind == :hr) ? (v > 25 && v < 230) : (v > 0 && v <= 100);
                if (valid) {
                    if (n == 0) {
                        t0 = s.when.value();
                    }
                    t1 = s.when.value();
                    n += 1;
                    last = v;
                    if (v < minV) { minV = v; }
                    if (v > maxV) { maxV = v; }
                    if (v <= 85) { low += 1; }
                }
            }
            s = it.next();
        }
        return (n > 0) ? [minV, maxV, last, n, t1 - t0, low] : null;
    }

    //! Localised notification text (resources with scope="background"; the
    //! language follows the watch, like the face).
    private function txt(id as ResourceId) as String {
        return Application.loadResource(id) as String;
    }

    //! Night = inside the typical sleep window from the user profile.
    private function isNight(profile as UserProfile.Profile, now as Number, tz as Number) as Boolean {
        var sleepS = (profile.sleepTime != null) ? (profile.sleepTime as Time.Duration).value() : 23 * 3600;
        var wakeS = (profile.wakeTime != null) ? (profile.wakeTime as Time.Duration).value() : 7 * 3600;
        var tod = ((now + tz) % 86400 + 86400) % 86400;
        return (sleepS > wakeS) ? (tod >= sleepS || tod < wakeS) : (tod >= sleepS && tod < wakeS);
    }

    //! Notification + log entry, respecting the rule's cooldown.
    private function fire(state as Array<Number>, rule as Number, now as Number,
                          title as String, body as String) as Void {
        if (now - state[3 + rule] < COOLDOWN[rule]) {
            return;
        }
        state[3 + rule] = now;
        if (Toybox has :Notifications) {
            Notifications.showNotification(title, "SOLAR·LAB", {
                :body => body,
                :actions => [] as Array<Notifications.Action>,
                :dismissPrevious => true
            });
        }
        var log = Application.Storage.getValue(LOG_KEY);
        var list = (log instanceof Array) ? log as Array<Application.Storage.ValueType> : [] as Array<Application.Storage.ValueType>;
        list.add([now, title] as Array<Application.Storage.ValueType>);
        while (list.size() > 5) {
            list = list.slice(1, null);
        }
        Application.Storage.setValue(LOG_KEY, list);
    }

    private function loadState() as Array<Number> {
        var s = Application.Storage.getValue(STATE_KEY);
        if (s instanceof Array && s.size() == 9) {
            return s as Array<Number>;
        }
        return [0, 0, 0, 0, 0, 0, 0, 0, 0] as Array<Number>;
    }
}
