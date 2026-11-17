import Toybox.Graphics;
import Toybox.Lang;
import Toybox.Math;
import Toybox.WatchUi;

//! Screen geometry and fonts for concept A ("Horizon") with the advice line
//! and traffic-light icons (concept A + B, chosen after the first watch test).
//! Coordinates are designed on a 416 px screen and scaled by height / 416,
//! so the same code works on other round screens.
//! Computed once in onLayout; renderers only read these values.
class LayoutManager {

    var width as Number;
    var height as Number;
    var cx as Number;
    var cy as Number;

    // Fonts (JetBrains Mono bitmaps, see resources/fonts)
    var timeFont as WatchUi.FontResource;
    var secFont as WatchUi.FontResource;
    var valueFont as WatchUi.FontResource;
    var dateFont as WatchUi.FontResource;
    var smallFont as WatchUi.FontResource;
    var tinyFont as WatchUi.FontResource;
    var actionFont as WatchUi.FontResource;   // bold Cyrillic: the one command
    var iconFont as WatchUi.FontResource;     // pictograms, tinted with setColor

    var batteryRowY as Number;    // battery percentage and days
    var dateY as Number;          // date line
    var timeY as Number;          // vertical centre of HH:MM
    var secondsY as Number;       // vertical centre of the seconds
    var ampmY as Number;          // AM / PM marker in 12-hour mode
    var adviceY as Number;        // the command, e.g. "ПОРА СПАТЬ"
    var reasonY as Number;        // why, e.g. "ЗАРЯД 22 · ВОССТ. 12 Ч"
    var slotX0 as Number;         // centre of the first icon
    var slotPitch as Number;      // distance between icon centres
    var iconY as Number;          // centre of the icon rings
    var iconR as Number;          // ring radius
    var slotValueY as Number;     // value under each icon

    var horizonY as Number;       // horizon line
    var horizonX0 as Number;
    var horizonX1 as Number;
    var sunTrackX0 as Number;     // sun disk travels between these x values
    var sunTrackX1 as Number;
    var sunLabelY as Number;      // sunrise / sunset labels
    var sunLabelX0 as Number;
    var sunLabelX1 as Number;
    var weatherY as Number;       // weather line
    var noteY as Number;          // small status note near the bottom

    var ringR as Number;          // 24 h balance ring at the very edge
    var ringPen as Number;

    var aodDateY as Number;       // always-on date line

    function initialize(dc as Dc) {
        width = dc.getWidth();
        height = dc.getHeight();
        cx = width / 2;
        cy = height / 2;

        timeFont = WatchUi.loadResource(Rez.Fonts.TimeFont) as WatchUi.FontResource;
        secFont = WatchUi.loadResource(Rez.Fonts.SecFont) as WatchUi.FontResource;
        valueFont = WatchUi.loadResource(Rez.Fonts.ValueFont) as WatchUi.FontResource;
        dateFont = WatchUi.loadResource(Rez.Fonts.DateFont) as WatchUi.FontResource;
        smallFont = WatchUi.loadResource(Rez.Fonts.SmallFont) as WatchUi.FontResource;
        tinyFont = WatchUi.loadResource(Rez.Fonts.TinyFont) as WatchUi.FontResource;
        actionFont = WatchUi.loadResource(Rez.Fonts.ActionFont) as WatchUi.FontResource;
        iconFont = WatchUi.loadResource(Rez.Fonts.IconFont) as WatchUi.FontResource;

        batteryRowY = px(46);
        dateY = px(84);
        timeY = px(146);
        secondsY = px(173);
        ampmY = px(121);
        adviceY = px(205);
        reasonY = px(228);
        slotX0 = px(76);
        slotPitch = px(88);
        iconY = px(264);
        iconR = px(22);
        slotValueY = px(302);

        horizonY = px(332);
        horizonX0 = px(66);
        horizonX1 = px(350);
        sunTrackX0 = px(44);
        sunTrackX1 = px(372);
        sunLabelY = px(346);
        sunLabelX0 = px(84);
        sunLabelX1 = px(332);
        weatherY = px(368);
        noteY = px(388);

        ringR = px(199);
        ringPen = px(6);

        aodDateY = px(118);
    }

    //! Converts a coordinate designed for 416 px into this screen's pixels.
    function px(v as Number) as Number {
        return (v * height / 416.0 + 0.5).toNumber();
    }
}
