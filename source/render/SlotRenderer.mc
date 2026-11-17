import Toybox.Graphics;
import Toybox.Lang;

//! Four metric slots as traffic lights: a pictogram inside a gauge ring, both in
//! the status colour (cyan fine, amber attention, coral act, grey no data), and
//! the value underneath (grey with an amber dot when the reading is old).
//! Colour answers "is it OK?", the gauge answers "how much?", the pictogram
//! itself carries meaning: the battery fills, the stress face smiles or frowns.
module SlotRenderer {

    // Gauge geometry in Graphics angles (0 = 3 o'clock, counter-clockwise):
    // from 7:30 clockwise over the top to 4:30
    const GAUGE_START = 225;
    const GAUGE_SPAN = 270;
    const GAUGE_END = 315;

    function draw(dc as Dc, l as LayoutManager, slots as Array<SlotModel>) as Void {
        if (dc has :setAntiAlias) {
            dc.setAntiAlias(true);
        }
        for (var i = 0; i < slots.size(); i++) {
            drawSlot(dc, l, slots[i], l.slotX0 + i * l.slotPitch);
        }
        if (dc has :setAntiAlias) {
            dc.setAntiAlias(false);
        }
    }

    function drawSlot(dc as Dc, l as LayoutManager, s as SlotModel, x as Number) as Void {
        // Three readable states only: cyan = fine (good or normal), amber = watch,
        // coral = act; grey = no data. White rings read as "grey / no data".
        var color = (s.level == Status.NORM) ? Palette.ACCENT : Palette.levelColor(s.level);
        var cy = l.iconY;
        var center = Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER;

        // Ring = gauge: a 270-degree dial open at the bottom. Dim track, the
        // filled part in the status colour shows how much (energy, stress, pulse
        // between rest and maximum, oxygen 80..100 %). No value: track only.
        dc.setPenWidth(l.px(3));
        dc.setColor(Palette.LINE, Graphics.COLOR_TRANSPARENT);
        dc.drawArc(x, cy, l.iconR, Graphics.ARC_CLOCKWISE, GAUGE_START, GAUGE_END);
        var f = s.fraction;
        if (f != null && s.level != Status.NONE) {
            var sweep = (GAUGE_SPAN * f).toNumber();
            if (sweep < 6) {
                sweep = 6;                         // keep a visible stub at zero
            }
            dc.setColor(color, Graphics.COLOR_TRANSPARENT);
            dc.drawArc(x, cy, l.iconR, Graphics.ARC_CLOCKWISE, GAUGE_START,
                (GAUGE_START - sweep + 360) % 360);
        }
        dc.setPenWidth(1);

        // Pictogram, tinted
        dc.drawText(x, cy, l.iconFont, s.icon, center);
        var meter = s.meter;
        if (meter != null) {
            // Battery fill inside the frame glyph (frame interior: 30 px glyph,
            // inner box about x +-5, y -9..+11 at 416 px)
            var inner = l.px(19);
            var fh = (inner * meter + 0.5).toNumber();
            if (fh > 0) {
                dc.fillRectangle(x - l.px(5), cy + l.px(11) - fh, l.px(11), fh);
            }
        }

        // Stale or off the personal norm: small amber dot on the ring
        if (s.stale || s.anomaly) {
            dc.setColor(Palette.WARN, Graphics.COLOR_TRANSPARENT);
            dc.fillCircle(x + l.iconR - l.px(3), cy - l.iconR + l.px(3), l.px(4));
        }

        // Value
        dc.setColor((s.level == Status.NONE || s.stale) ? Palette.MUTED : Palette.FG,
            Graphics.COLOR_TRANSPARENT);
        dc.drawText(x, l.slotValueY, l.valueFont, s.value, center);

    }
}
