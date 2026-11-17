import Toybox.Graphics;
import Toybox.Lang;
import Toybox.Math;
import Toybox.System;
import Toybox.Time.Gregorian;

//! Full presentation of concept A, drawn while the watch is awake.
//! Order: sky with sun and mountains, 24 h ring, battery, date, time, seconds,
//! advice line, traffic-light icons, horizon line, sunrise/sunset, weather, note.
module FaceRenderer {

    function draw(dc as Dc, l as LayoutManager, clock as System.ClockTime,
                  date as Gregorian.Info, showSeconds as Boolean,
                  sky as SkyRenderer, solar as SolarState, health as HealthData,
                  slots as Array<SlotModel>, advice as Advice,
                  weather as WeatherInfo, event as String?) as Void {
        sky.draw(dc);
        RingRenderer.draw(dc, l, health, clock.hour * 60 + clock.min);
        drawBattery(dc, l);
        drawDate(dc, l, date);
        drawTime(dc, l, clock, showSeconds);
        drawAdvice(dc, l, advice);
        SlotRenderer.draw(dc, l, slots);
        drawHorizon(dc, l, solar);
        drawWeather(dc, l, weather);
        drawNote(dc, l, solar, event);
    }

    //! The command in its status colour (with a moon at night) and the reason.
    function drawAdvice(dc as Dc, l as LayoutManager, a as Advice) as Void {
        var just = Graphics.TEXT_JUSTIFY_LEFT | Graphics.TEXT_JUSTIFY_VCENTER;
        var w = dc.getTextWidthInPixels(a.text, l.actionFont);
        var icon = a.icon;
        var iw = (icon != null) ? l.px(34) : 0;
        var x = l.cx - (w + iw) / 2;
        dc.setColor(Palette.levelColor(a.level), Graphics.COLOR_TRANSPARENT);
        if (icon != null) {
            dc.drawText(x, l.adviceY, l.iconFont, icon, just);
        }
        dc.drawText(x + iw, l.adviceY, l.actionFont, a.text, just);
        var detail = a.detail;
        if (detail.length() > 0) {
            // Two reasons that do not fit the line: keep the first (most severe)
            if (dc.getTextWidthInPixels(detail, l.smallFont) > l.px(380)) {
                var cut = detail.find(" · ");
                if (cut != null) {
                    detail = detail.substring(0, cut) as String;
                }
            }
            dc.setColor(Palette.SOFT, Graphics.COLOR_TRANSPARENT);
            dc.drawText(l.cx, l.reasonY, l.smallFont, detail,
                Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
        }
    }

    //! Weather parts separated by wide gaps, each in its own status colour.
    function drawWeather(dc as Dc, l as LayoutManager, w as WeatherInfo) as Void {
        var n = w.parts.size();
        if (n == 0) {
            return;
        }
        var gap = l.px(12);
        var total = gap * (n - 1);
        for (var i = 0; i < n; i++) {
            total += dc.getTextWidthInPixels(w.parts[i], l.smallFont);
        }
        var x = l.cx - total / 2;
        var just = Graphics.TEXT_JUSTIFY_LEFT | Graphics.TEXT_JUSTIFY_VCENTER;
        for (var i = 0; i < n; i++) {
            var level = w.levels[i];
            var color = Palette.FG;       // white: the bottom line must read at a glance
            if (w.stale) {
                color = Palette.MUTED;
            } else if (level != Status.NORM) {
                color = Palette.levelColor(level);
            }
            dc.setColor(color, Graphics.COLOR_TRANSPARENT);
            dc.drawText(x, l.weatherY, l.smallFont, w.parts[i], just);
            x += dc.getTextWidthInPixels(w.parts[i], l.smallFont) + gap;
        }
    }

    //! Watch battery as "72%  9D" at the top (the edge belongs to the 24 h ring).
    //! Colour follows the status.
    function drawBattery(dc as Dc, l as LayoutManager) as Void {
        var stats = System.getSystemStats();
        var pct = stats.battery;                      // Float, 0..100
        var color = Palette.ACCENT;
        if (pct < 15) {
            color = Palette.ALERT;
        } else if (pct < 30) {
            color = Palette.WARN;
        }

        var pctText = pct.toNumber().format("%d") + "%";
        var daysText = (pct < 15) ? "CHARGE" : stats.batteryInDays.toNumber().format("%d") + "D";
        var gap = l.px(6);
        var w1 = dc.getTextWidthInPixels(pctText, l.smallFont);
        var w2 = dc.getTextWidthInPixels(daysText, l.smallFont);
        var x = l.cx - (w1 + gap + w2) / 2;
        dc.setColor(pct < 30 ? color : Palette.FG, Graphics.COLOR_TRANSPARENT);
        dc.drawText(x, l.batteryRowY, l.smallFont, pctText,
            Graphics.TEXT_JUSTIFY_LEFT | Graphics.TEXT_JUSTIFY_VCENTER);
        dc.setColor(pct < 15 ? Palette.ALERT : Palette.LABEL, Graphics.COLOR_TRANSPARENT);
        dc.drawText(x + w1 + gap, l.batteryRowY, l.smallFont, daysText,
            Graphics.TEXT_JUSTIFY_LEFT | Graphics.TEXT_JUSTIFY_VCENTER);
    }

    //! "SAT 07 NOV · W45" in grey with the day number in white.
    function drawDate(dc as Dc, l as LayoutManager, date as Gregorian.Info) as Void {
        var parts = DateUtil.dateParts(date);          // [prefix, day, suffix]
        var w0 = dc.getTextWidthInPixels(parts[0], l.dateFont);
        var w1 = dc.getTextWidthInPixels(parts[1], l.dateFont);
        var w2 = dc.getTextWidthInPixels(parts[2], l.dateFont);
        var x = l.cx - (w0 + w1 + w2) / 2;
        var just = Graphics.TEXT_JUSTIFY_LEFT | Graphics.TEXT_JUSTIFY_VCENTER;
        dc.setColor(Palette.SOFT, Graphics.COLOR_TRANSPARENT);
        dc.drawText(x, l.dateY, l.dateFont, parts[0], just);
        dc.setColor(Palette.FG, Graphics.COLOR_TRANSPARENT);
        dc.drawText(x + w0, l.dateY, l.dateFont, parts[1], just);
        dc.setColor(Palette.SOFT, Graphics.COLOR_TRANSPARENT);
        dc.drawText(x + w0 + w1, l.dateY, l.dateFont, parts[2], just);
    }

    //! HH:MM in thin digits with a grey colon; cyan seconds to the right.
    function drawTime(dc as Dc, l as LayoutManager, clock as System.ClockTime,
                      showSeconds as Boolean) as Void {
        var hh = DateUtil.hourString(clock);
        var mm = clock.min.format("%02d");
        var wh = dc.getTextWidthInPixels(hh, l.timeFont);
        var wc = dc.getTextWidthInPixels(":", l.timeFont);
        var wm = dc.getTextWidthInPixels(mm, l.timeFont);
        var x = l.cx - (wh + wc + wm) / 2;
        var just = Graphics.TEXT_JUSTIFY_LEFT | Graphics.TEXT_JUSTIFY_VCENTER;

        dc.setColor(Palette.FG, Graphics.COLOR_TRANSPARENT);
        dc.drawText(x, l.timeY, l.timeFont, hh, just);
        dc.setColor(Palette.MUTED, Graphics.COLOR_TRANSPARENT);
        dc.drawText(x + wh, l.timeY, l.timeFont, ":", just);
        dc.setColor(Palette.FG, Graphics.COLOR_TRANSPARENT);
        dc.drawText(x + wh + wc, l.timeY, l.timeFont, mm, just);

        if (showSeconds) {
            dc.setColor(Palette.ACCENT, Graphics.COLOR_TRANSPARENT);
            dc.drawText(x + wh + wc + wm + l.px(4), l.secondsY, l.secFont,
                clock.sec.format("%02d"), just);
        }
        // 12-hour mode: without AM / PM, 00:41 and 12:41 look the same
        if (!System.getDeviceSettings().is24Hour) {
            dc.setColor(Palette.SOFT, Graphics.COLOR_TRANSPARENT);
            dc.drawText(x + wh + wc + wm + l.px(4), l.ampmY, l.tinyFont,
                clock.hour < 12 ? "AM" : "PM", just);
        }
    }

    //! Horizon line and sunrise / sunset times under it.
    //! The sun itself is part of the sky (SkyRenderer), behind the mountains.
    function drawHorizon(dc as Dc, l as LayoutManager, solar as SolarState) as Void {
        dc.setColor(Palette.LINE, Graphics.COLOR_TRANSPARENT);
        dc.drawLine(l.horizonX0, l.horizonY, l.horizonX1, l.horizonY);

        // Sunrise (left, small up-triangle) and sunset (right, small down-triangle)
        var riseText = "--:--";
        var setText = "--:--";
        var rise = solar.riseMin;
        if (rise != null) {
            riseText = DateUtil.minutesToHhmm(rise);
        }
        var sunset = solar.setMin;
        if (sunset != null) {
            setText = DateUtil.minutesToHhmm(sunset);
        }
        var y = l.sunLabelY;
        var t = l.px(4);
        dc.setColor(Palette.SOFT, Graphics.COLOR_TRANSPARENT);
        dc.fillPolygon([[l.sunLabelX0, y + t - 1], [l.sunLabelX0 + t, y - t + 1],
                        [l.sunLabelX0 + 2 * t, y + t - 1]]);
        dc.drawText(l.sunLabelX0 + 2 * t + l.px(4), y, l.smallFont, riseText,
            Graphics.TEXT_JUSTIFY_LEFT | Graphics.TEXT_JUSTIFY_VCENTER);
        dc.fillPolygon([[l.sunLabelX1 - 2 * t, y - t + 1], [l.sunLabelX1, y - t + 1],
                        [l.sunLabelX1 - t, y + t - 1]]);
        dc.drawText(l.sunLabelX1 - 2 * t - l.px(4), y, l.smallFont, setText,
            Graphics.TEXT_JUSTIFY_RIGHT | Graphics.TEXT_JUSTIFY_VCENTER);

    }

    //! Bottom note: the last sentinel event (amber, 12 h), else a missing location.
    function drawNote(dc as Dc, l as LayoutManager, solar as SolarState, event as String?) as Void {
        var text = "";
        var color = Palette.WARN;
        if (event != null) {
            text = event;
        } else if (solar.hasFix) {
            return;
        } else {
            text = Tr.s(Rez.Strings.NoteDefaultLocation);
            color = Palette.NOTE;
        }
        // The note sits low on the round screen: cut the text to the chord
        // inside the ring there, so a long event or translation never runs
        // into the ring
        var dy = (l.noteY - l.cy).toFloat();
        var r = (l.ringR - l.px(12)).toFloat();
        var maxW = (r > dy.abs()) ? (2.0 * Math.sqrt(r * r - dy * dy)).toNumber() : l.px(100);
        while (text.length() > 4 && dc.getTextWidthInPixels(text, l.tinyFont) > maxW) {
            text = text.substring(0, text.length() - 1) as String;
        }
        dc.setColor(color, Graphics.COLOR_TRANSPARENT);
        dc.drawText(l.cx, l.noteY, l.tinyFont, text, Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
    }
}
