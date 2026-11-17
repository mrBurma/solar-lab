import Toybox.Graphics;
import Toybox.Lang;
import Toybox.Math;

//! Perimeter ring "24-hour balance": the last 23 hours on a 24-hour dial, noon at
//! the top and midnight at the bottom, in 15-minute segments with a small gap at
//! every hour. Segment colour:
//!   lavender Body Battery rose (sleep, calm rest); the sky palette, so the
//!            ring stays context and the cyan icons keep the attention
//!   amber    heart rate in the moderate zone or above (intensity minutes)
//!   slate    ordinary time, energy being spent
//!   track    no data
//! The ring ends at "now": the empty hour after it separates today from
//! yesterday, so no extra pointer is drawn.
//! Outside the ring, on the screen edge: a thin green arc for the sleep window from the Garmin profile.
//! Marks: quarter ticks at 0, 6, 12 and 18 h.
module RingRenderer {

    const DRAIN = 0x2C3644;
    const BUCKET_DEG = 3.75;          // 15 minutes on a 24-hour dial
    const HOUR_GAP = 1.2;             // degrees left empty at the end of each hour

    function draw(dc as Dc, l as LayoutManager, h as HealthData, minuteOfDay as Number) as Void {
        var state = h.ringState;
        var active = h.ringActive;
        var n = state.size();
        var nowBucket = minuteOfDay / 15;
        dc.setPenWidth(l.ringPen);

        // Walk the 93 buckets ending with "now", oldest first; merge equal
        // neighbours inside one hour into one arc
        var runStart = -1;
        var runColor = 0;
        for (var k = 0; k <= 93; k++) {
            var b = (nowBucket - 92 + k + n) % n;
            var c = (k < 93) ? (active[b] ? Palette.WARN : colorOf(state[b])) : -1;
            var hourStart = (b % 4 == 0);
            if (runStart >= 0 && (c != runColor || hourStart || k == 93)) {
                // close the run that ends just before bucket b
                var endB = (b + n - 1) % n;
                var gap = ((endB + 1) % 4 == 0) ? HOUR_GAP : 0.0;
                arc(dc, l, l.ringR, runStart * BUCKET_DEG, (endB + 1) * BUCKET_DEG - gap, runColor);
                runStart = -1;
            }
            if (runStart < 0 && k < 93) {
                runStart = b;
                runColor = c;
            }
        }

        // Sleep window from the profile: a green line on the very edge, outside
        // the ring, so it can never touch the icons, the horizon or the labels
        dc.setPenWidth(l.px(3));
        dc.setColor(Palette.SLEEP, Graphics.COLOR_TRANSPARENT);
        var rs = l.ringR + l.px(6);
        dc.drawArc(l.cx, l.cy, rs, Graphics.ARC_CLOCKWISE,
            graphicsAngle(h.sleepMinute / 4.0), graphicsAngle(h.wakeMinute / 4.0));

        // Quarter ticks: 0, 6, 12, 18 h
        dc.setPenWidth(1);
        dc.setColor(Palette.SOFT, Graphics.COLOR_TRANSPARENT);
        for (var q = 0; q < 4; q++) {
            radial(dc, l, q * 360, l.ringR - l.px(11), l.cy);
        }
    }

    //! Segment state to colour; -1 never drawn.
    function colorOf(s as Number) as Number {
        if (s == RingState.CHARGE) {
            return Palette.CHARGE;
        }
        if (s == RingState.DRAIN) {
            return DRAIN;
        }
        return Palette.TRACK;
    }

    //! Clockwise arc between two dial angles (degrees from midnight, clockwise
    //! from the bottom), in one colour.
    function arc(dc as Dc, l as LayoutManager, r as Number, d0 as Float, d1 as Float, color as Number) as Void {
        if (d1 - d0 < 0.5) {
            return;
        }
        dc.setColor(color, Graphics.COLOR_TRANSPARENT);
        dc.drawArc(l.cx, l.cy, r, Graphics.ARC_CLOCKWISE, graphicsAngle(d0), graphicsAngle(d1));
    }

    //! Dial angle (degrees from midnight at the bottom, clockwise) to a Graphics
    //! angle (degrees, 0 = 3 o'clock, counter-clockwise), normalised to 0..360.
    function graphicsAngle(dial as Float) as Float {
        var a = 90.0 - (dial + 180.0);
        while (a < 0.0) {
            a += 360.0;
        }
        while (a >= 360.0) {
            a -= 360.0;
        }
        return a;
    }

    //! Short radial line at a minute of day, between radii r0 and r1.
    function radial(dc as Dc, l as LayoutManager, minute as Number, r0 as Number, r1 as Number) as Void {
        var rad = Math.toRadians(minute / 4.0 + 180.0);
        var p0 = point(l, rad, r0);
        var p1 = point(l, rad, r1);
        dc.drawLine(p0[0], p0[1], p1[0], p1[1]);
    }

    //! Screen point at a dial angle (radians, clockwise from 12 o'clock) and radius.
    function point(l as LayoutManager, rad as Numeric, r as Number) as [Number, Number] {
        return [l.cx + (r * Math.sin(rad)).toNumber(), l.cy - (r * Math.cos(rad)).toNumber()];
    }
}
