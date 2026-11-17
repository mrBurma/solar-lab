import Toybox.Lang;
import Toybox.WatchUi;

//! The one command on the face: what to do right now, in plain words (English or
//! Russian, following the watch language; texts in resources/strings), so the
//! numbers do not have to be interpreted. Exactly one advice is chosen, the most
//! important first:
//!   sleep window                  ПОРА СПАТЬ        colour from readiness
//!   current stress >= 76          ПОДЫШИ 2 МИН      amber
//!   move bar (1 h+ without moving) ПОРА РАЗМЯТЬСЯ   amber (day only)
//!   readiness REST                ДЕНЬ ОТДЫХА       coral (evening: ЛЯГ ПОРАНЬШЕ)
//!   readiness EASY                ЛЁГКАЯ НАГРУЗКА   amber (evening: СПОКОЙНЫЙ ВЕЧЕР)
//!   readiness READY, morning      МОЖНО ТРЕНИРОВАТЬСЯ cyan
//!   readiness READY               ВСЁ В НОРМЕ       cyan
//!   no data                       НЕТ ДАННЫХ        grey
//! The second line gives the reason (from Readiness, or the triggering value).
class Advice {

    var text as String = "";
    var detail as String = "";
    var level as Number = Status.NONE;
    var icon as String? = null;        // optional pictogram before the text (moon)

    function initialize() {
    }

    function update(phase as Number, r as Readiness, h as HealthData, now as Number) as Void {
        icon = null;
        detail = r.detail;

        if (phase == Slots.NIGHT) {
            text = Tr.s(Rez.Strings.AdvSleep);
            icon = "x";
            level = (r.level == Status.NONE) ? Status.NORM : r.level;
            return;
        }

        var stress = h.stress;
        if (stress != null && !h.stressStale && stress >= 76) {
            text = Tr.s(Rez.Strings.AdvBreathe);
            detail = Tr.f(Rez.Strings.DetStress, [stress]);
            level = Status.WARN;
            return;
        }

        // Move bar from Garmin, but silenced for an hour after our own step
        // counter saw a walk (the move bar itself was seen to lag on the watch)
        var move = h.moveLevel;
        if (move != null && move >= 1 && now - h.movedAt > 3600) {
            text = Tr.s(Rez.Strings.AdvMove);
            // Garmin's move bar fills after an hour without moving and clears after
            // a couple of minutes of walking: say what to do, not a guessed time
            detail = Tr.s(Rez.Strings.DetMove);
            level = Status.WARN;
            return;
        }

        var evening = (phase == Slots.EVENING);
        if (r.level == Status.ALERT) {
            text = Tr.s(evening ? Rez.Strings.AdvBedEarly : Rez.Strings.AdvRestDay);
            level = Status.ALERT;
        } else if (r.level == Status.WARN) {
            text = Tr.s(evening ? Rez.Strings.AdvCalmEvening : Rez.Strings.AdvLight);
            level = Status.WARN;
        } else if (r.level == Status.GOOD) {
            text = Tr.s((phase == Slots.MORNING) ? Rez.Strings.AdvTrain : Rez.Strings.AdvOk);
            level = Status.GOOD;
        } else {
            text = Tr.s(Rez.Strings.AdvNoData);
            level = Status.NONE;
        }
    }
}
