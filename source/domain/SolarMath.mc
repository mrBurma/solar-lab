import Toybox.Lang;
import Toybox.Math;

//! Solar position from the NOAA "General Solar Position" equations
//! (Spencer Fourier series for declination and equation of time).
//! Accuracy is about one minute for sunrise/sunset at mid latitudes,
//! far better than the colour model needs. Pure functions, no state.
module SolarMath {

    const DEG = 0.017453292519943295;   // pi / 180

    //! Fractional year in radians for a day of year and local minutes after midnight.
    function gamma(doy as Number, minutes as Float) as Float {
        return (2.0 * Math.PI / 365.0 * (doy - 1 + (minutes / 60.0 - 12.0) / 24.0)).toFloat();
    }

    //! Solar declination in radians.
    function declination(g as Float) as Float {
        return (0.006918 - 0.399912 * Math.cos(g) + 0.070257 * Math.sin(g)
            - 0.006758 * Math.cos(2 * g) + 0.000907 * Math.sin(2 * g)
            - 0.002697 * Math.cos(3 * g) + 0.00148 * Math.sin(3 * g)).toFloat();
    }

    //! Equation of time in minutes.
    function equationOfTime(g as Float) as Float {
        return (229.18 * (0.000075 + 0.001868 * Math.cos(g) - 0.032077 * Math.sin(g)
            - 0.014615 * Math.cos(2 * g) - 0.040849 * Math.sin(2 * g))).toFloat();
    }

    //! Sun elevation above the horizon in degrees (negative below it).
    //! lat/lon in degrees (east positive), tzHours includes daylight saving.
    function elevation(lat as Float, lon as Float, tzHours as Float,
                       doy as Number, minutes as Float) as Float {
        var g = gamma(doy, minutes);
        var decl = declination(g);
        var offset = equationOfTime(g) + 4.0 * lon - 60.0 * tzHours;
        var hourAngle = ((minutes + offset) / 4.0 - 180.0) * DEG;
        var phi = lat * DEG;
        var cosZenith = Math.sin(phi) * Math.sin(decl)
            + Math.cos(phi) * Math.cos(decl) * Math.cos(hourAngle);
        if (cosZenith > 1.0) {
            cosZenith = 1.0;
        } else if (cosZenith < -1.0) {
            cosZenith = -1.0;
        }
        return (90.0 - Math.acos(cosZenith) / DEG).toFloat();
    }

    //! Sunrise and sunset in local minutes after midnight, using the standard
    //! -0.833 degree horizon (refraction plus solar radius).
    //! Returns null during polar day or polar night.
    function sunTimes(lat as Float, lon as Float, tzHours as Float, doy as Number) as Array<Float>? {
        var g = gamma(doy, 720.0);
        var decl = declination(g);
        var phi = lat * DEG;
        var cosH = (Math.sin(-0.833 * DEG) - Math.sin(phi) * Math.sin(decl))
            / (Math.cos(phi) * Math.cos(decl));
        if (cosH > 1.0 || cosH < -1.0) {
            return null;
        }
        var halfDay = 4.0 * Math.acos(cosH) / DEG;                       // minutes
        var noon = 720.0 - 4.0 * lon - equationOfTime(g) + 60.0 * tzHours;
        return [(noon - halfDay).toFloat(), (noon + halfDay).toFloat()] as Array<Float>;
    }
}
