import Toybox.Graphics;
import Toybox.Lang;
import Toybox.System;
import Toybox.Time.Gregorian;

//! Always-on presentation of concept A. Rules for AMOLED low power:
//! - black background, no sky, no arcs, no accent colours;
//! - thin dimmed time and a short date only, well under 10 % of screen luminance;
//! - the whole group shifts every minute (dx, dy) to prevent burn-in;
//! - no seconds, no expensive calculations.
module AodRenderer {

    function draw(dc as Dc, l as LayoutManager, clock as System.ClockTime,
                  date as Gregorian.Info, dx as Number, dy as Number) as Void {
        dc.setColor(Graphics.COLOR_BLACK, Graphics.COLOR_BLACK);
        dc.clear();

        dc.setColor(Palette.AOD_DIM, Graphics.COLOR_TRANSPARENT);
        dc.drawText(l.cx + dx, l.aodDateY + dy, l.dateFont, DateUtil.dateShort(date),
            Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);

        dc.setColor(Palette.AOD_TIME, Graphics.COLOR_TRANSPARENT);
        dc.drawText(l.cx + dx, l.timeY + dy, l.timeFont,
            DateUtil.hourString(clock) + ":" + clock.min.format("%02d"),
            Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
    }
}
