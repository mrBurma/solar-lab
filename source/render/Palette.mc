import Toybox.Lang;

//! Colour system of concept A. Warm colours belong to the sky only
//! (from sunrise.glsl); cyan is the single data accent; amber and coral
//! are reserved for statuses.
module Palette {
    const BG       = 0x050505;  // near-black ground
    const FG       = 0xF2F4F7;  // cool white, primary text
    const MUTED    = 0x737B87;  // technical grey, secondary text
    const LABEL    = 0x8C939F;  // date and battery labels, readable over the sky
    const SOFT     = 0xC9C4D6;  // sunrise / sunset and slot labels (lavender-grey of the hills)
    const LINE     = 0x3A3F4A;  // horizon line
    const NOTE     = 0x5A6170;  // very quiet notes
    const TRACK    = 0x1C2028;  // empty part of arcs and the 24 h ring
    const SLEEP    = 0x4FD08A;  // sleep window arc on the 24 h ring (green, stands apart from the lavender charge)
    const CHARGE   = 0x8C7CE8;  // Body Battery charging on the 24 h ring (lavender of the sky)
    const SCALE    = 0x2A2F38;  // empty part of the slot micro scales

    const ACCENT   = 0x00D5FF;  // data accent, "good" status
    const WARN     = 0xFFB347;  // GFX_PRIMARY, "attention" status
    const ALERT    = 0xFF6F61;  // GFX_ACCENT, "problem" status
    const SUN      = 0xFFE7B0;  // sun disk
    // 64-colour (MIP) screens: exact palette entries, no dithering needed
    const SUN_MIP       = 0xFFAA00;
    const HILL_FAR_MIP  = 0x005555;
    const HILL_NEAR_MIP = 0x000055;

    const AOD_TIME = 0x8A919C;  // dimmed time for always-on
    const AOD_DIM  = 0x4A4858;  // dimmed secondary text for always-on

    //! Status level (Status.GOOD .. Status.NONE) to its colour.
    function levelColor(level as Lang.Number) as Lang.Number {
        if (level == Status.GOOD) { return ACCENT; }
        if (level == Status.NORM) { return FG; }
        if (level == Status.WARN) { return WARN; }
        if (level == Status.ALERT) { return ALERT; }
        return MUTED;
    }
}
