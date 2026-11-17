import Toybox.Lang;

//! Summary status READY / EASY / REST with the reasons that pull it down.
//! Reasons are short Russian phrases shown under the advice line. They explain
//! rather than repeat: values already on the icons (Body Battery) are not quoted.
//!
//! Deliberately not a 0-100 index: the rules below are transparent heuristics,
//! not a calibrated model, and a number would look like a medical score.
//!   REST  any of: Body Battery <= 25, resting HR >= norm + 7, recovery > 24 h
//!   EASY  any of: Body Battery <= 50, resting HR >= norm + 4, recovery > 0,
//!         overnight charge < 25, average stress today > 50, night SpO2 <= 85 (wrist sensor),
//!         overnight charge or stress outside the personal 2-sigma band
//!   READY otherwise
//! The resting HR norm is the personal baseline once 7 nights are stored,
//! Garmin's average resting HR before that.
class Readiness {

    var word as String = "NO DATA";
    var level as Number = Status.NONE;
    var detail as String = "";

    private var _texts as Array<String> = [] as Array<String>;
    private var _sev as Array<Number> = [] as Array<Number>;

    function initialize() {
    }

    function update(h as HealthData, b as Baseline) as Void {
        _texts = [] as Array<String>;
        _sev = [] as Array<Number>;
        var inputs = 0;

        var bb = h.bb;
        if (bb != null) {
            inputs += 1;
            if (bb <= 25) {
                add(Tr.s(Rez.Strings.RsnEnergyZero), Status.ALERT);
            } else if (bb <= 50) {
                add(Tr.s(Rez.Strings.RsnEnergyLow), Status.WARN);
            }
        }

        var delta = rhrDelta(h, b);
        if (delta != null) {
            inputs += 1;
            var text = Tr.f(Rez.Strings.RsnRhr, ["+" + delta.format("%d")]);
            if (delta >= 7) {
                add(text, Status.ALERT);
            } else if (delta >= 4) {
                add(text, Status.WARN);
            } else if (b.isAnomaly(Baseline.RHR, h.nightRhr)) {
                add(Tr.s(Rez.Strings.RsnRhrUp), Status.WARN);
            }
        }

        var rec = h.recoveryMin;
        if (rec != null) {
            inputs += 1;
            var hours = (rec + 59) / 60;
            if (hours > 24) {
                add(Tr.f(Rez.Strings.RsnRecovery, [hours]), Status.ALERT);
            } else if (hours > 0) {
                add(Tr.f(Rez.Strings.RsnRecovery, [hours]), Status.WARN);
            }
        }

        var charge = h.charge;
        if (charge != null) {
            inputs += 1;
            if (charge < 25 || b.isAnomaly(Baseline.CHARGE, charge)) {
                add(Tr.s(Rez.Strings.RsnNightWeak), Status.WARN);
            }
        }

        var stress = h.stressAvg;
        if (stress != null && (stress > 50 || b.isAnomaly(Baseline.STRESS, stress))) {
            add(Tr.s(Rez.Strings.RsnStressDay), Status.WARN);
        }

        var spo2 = h.spo2NightMin;
        if (spo2 != null && spo2 <= 85) {          // wrist bands, see Status.spo2
            add(Tr.f(Rez.Strings.RsnSpo2Night, [spo2]), Status.WARN);
        }

        if (inputs == 0) {
            word = "NO DATA";
            level = Status.NONE;
            detail = "";
            return;
        }

        var worst = Status.GOOD;
        for (var i = 0; i < _sev.size(); i++) {
            if (_sev[i] == Status.ALERT) {
                worst = Status.ALERT;
            } else if (_sev[i] == Status.WARN && worst != Status.ALERT) {
                worst = Status.WARN;
            }
        }
        if (worst == Status.ALERT) {
            word = "REST";
        } else if (worst == Status.WARN) {
            word = "EASY";
        } else {
            word = "READY";
        }
        level = worst;

        if (worst == Status.GOOD) {
            // Nothing pulls down: show what supports the verdict
            var parts = [] as Array<String>;
            if (bb != null) {
                parts.add(Tr.s(Rez.Strings.RsnEnergyOk));
            }
            if (charge != null) {
                parts.add(Tr.f(Rez.Strings.RsnNight, [charge]));
            } else if (delta != null) {
                parts.add(Tr.f(Rez.Strings.RsnRhr, [delta < 0 ? "−" + (-delta).format("%d") : "+" + delta.format("%d")]));
            }
            detail = join(parts);
        } else {
            detail = join(topReasons());
        }
    }

    //! Today's resting HR minus the personal or Garmin norm.
    static function rhrDelta(h as HealthData, b as Baseline) as Number? {
        var today = h.rhrToday();
        if (today == null) {
            return null;
        }
        var ref = b.mean(Baseline.RHR);
        if (ref != null) {
            return today - (ref + 0.5).toNumber();
        }
        var avg = h.rhrAverage;
        return (avg != null) ? today - avg : null;
    }

    private function add(text as String, severity as Number) as Void {
        _texts.add(text);
        _sev.add(severity);
    }

    //! Up to two reasons, the most severe first.
    private function topReasons() as Array<String> {
        var out = [] as Array<String>;
        for (var pass = 0; pass < 2; pass++) {
            var wanted = (pass == 0) ? Status.ALERT : Status.WARN;
            for (var i = 0; i < _texts.size() && out.size() < 2; i++) {
                if (_sev[i] == wanted) {
                    out.add(_texts[i]);
                }
            }
        }
        return out;
    }

    private function join(parts as Array<String>) as String {
        var s = "";
        for (var i = 0; i < parts.size(); i++) {
            s += (i == 0) ? parts[i] : " · " + parts[i];
        }
        return s;
    }
}
