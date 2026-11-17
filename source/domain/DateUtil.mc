import Toybox.Lang;
import Toybox.System;
import Toybox.Time.Gregorian;

//! Date and time formatting in a compact technical style: "MON 09 NOV · W46"
//! ("ПН 09 НОЯ · Н46" on a Russian watch). Day and month names come from the
//! string resources, so they follow the watch language.
module DateUtil {

    var _days as Array<String>? = null;      // Sunday first
    var _months as Array<String>? = null;

    function dayName(dow as Number) as String {
        var d = _days;
        if (d == null) {
            d = Tr.words(Rez.Strings.Days);
            _days = d;
        }
        return d[dow % 7];
    }

    function monthName(m as Number) as String {
        var a = _months;
        if (a == null) {
            a = Tr.words(Rez.Strings.Months);
            _months = a;
        }
        return a[m - 1];
    }

    // Lookup tables, allocated once.
    const SAKAMOTO = [0, 3, 2, 5, 0, 3, 5, 1, 4, 6, 2, 4] as Array<Number>;
    const CUM_DAYS = [0, 31, 59, 90, 120, 151, 181, 212, 243, 273, 304, 334] as Array<Number>;

    //! "07:58" in 24-hour mode, "7:58" in 12-hour mode (follows the watch setting).
    function timeString(clock as System.ClockTime) as String {
        var hour = clock.hour;
        if (!System.getDeviceSettings().is24Hour) {
            hour = hour % 12;
            if (hour == 0) {
                hour = 12;
            }
            return hour.format("%d") + ":" + clock.min.format("%02d");
        }
        return hour.format("%02d") + ":" + clock.min.format("%02d");
    }

    //! Hours only: "07" in 24-hour mode, "7" in 12-hour mode.
    function hourString(clock as System.ClockTime) as String {
        var hour = clock.hour;
        if (!System.getDeviceSettings().is24Hour) {
            hour = hour % 12;
            if (hour == 0) {
                hour = 12;
            }
            return hour.format("%d");
        }
        return hour.format("%02d");
    }

    //! Date split for two-tone drawing: ["MON ", "09", " NOV · W46"].
    function dateParts(date as Gregorian.Info) as Array<String> {
        var y = date.year as Number;
        var m = date.month as Number;
        var d = date.day as Number;
        return [dayName(isoDayOfWeek(y, m, d)) + " ", d.format("%02d"),
                " " + monthName(m) + " · " + Tr.s(Rez.Strings.Week) + isoWeek(y, m, d).format("%d")] as Array<String>;
    }

    //! "SAT 07 NOV  W45"
    function dateLine(date as Gregorian.Info) as String {
        var y = date.year as Number;
        var m = date.month as Number;
        var d = date.day as Number;
        var dow = isoDayOfWeek(y, m, d);
        return dayName(dow) + " " + d.format("%02d") + " " + monthName(m)
            + "  " + Tr.s(Rez.Strings.Week) + isoWeek(y, m, d).format("%d");
    }

    //! "SAT 07" for the always-on screen.
    function dateShort(date as Gregorian.Info) as String {
        var y = date.year as Number;
        var m = date.month as Number;
        var d = date.day as Number;
        return dayName(isoDayOfWeek(y, m, d)) + " " + d.format("%02d");
    }

    //! Local minutes after midnight (may be fractional) to "07:47", always 24-hour.
    function minutesToHhmm(minutes as Float) as String {
        var m = (minutes + 0.5).toNumber();
        m = ((m % 1440) + 1440) % 1440;
        return (m / 60).format("%02d") + ":" + (m % 60).format("%02d");
    }

    //! ISO 8601 day of week: Monday = 1 ... Sunday = 7 (Sakamoto's method).
    function isoDayOfWeek(y as Number, m as Number, d as Number) as Number {
        var yy = (m < 3) ? y - 1 : y;
        var w = (yy + yy / 4 - yy / 100 + yy / 400 + SAKAMOTO[m - 1] + d) % 7;
        return (w == 0) ? 7 : w;
    }

    function isLeap(y as Number) as Boolean {
        return (y % 4 == 0 && y % 100 != 0) || (y % 400 == 0);
    }

    function dayOfYear(y as Number, m as Number, d as Number) as Number {
        var n = CUM_DAYS[m - 1] + d;
        if (m > 2 && isLeap(y)) {
            n += 1;
        }
        return n;
    }

    //! A year has 53 ISO weeks if it starts on Thursday,
    //! or on Wednesday in a leap year.
    function weeksInYear(y as Number) as Number {
        var jan1 = isoDayOfWeek(y, 1, 1);
        return (jan1 == 4 || (jan1 == 3 && isLeap(y))) ? 53 : 52;
    }

    //! ISO 8601 week number (1..53).
    function isoWeek(y as Number, m as Number, d as Number) as Number {
        var week = (dayOfYear(y, m, d) - isoDayOfWeek(y, m, d) + 10) / 7;
        if (week < 1) {
            return weeksInYear(y - 1);
        }
        if (week > weeksInYear(y)) {
            return 1;
        }
        return week;
    }
}
