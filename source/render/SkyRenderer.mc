import Toybox.Graphics;
import Toybox.Lang;
import Toybox.Math;
import Toybox.System;

//! Sky and mountains: a port of GhostFX sunrise.glsl (MIT, github.com/r3dg0d/ghostfx).
//! In the shader the sun rises on a 90-second timer; here its height comes from the
//! real solar elevation. Differences from the shader, all deliberate:
//! - colour per 1 px row instead of per pixel (the tight sun glow becomes a halo ring);
//! - rows are dithered to RGB565 so the dark gradient shows no bands on a 16-bit display;
//! - deep night (below about -6 degrees) fades to a dark navy with a faint airglow at
//!   the horizon instead of the shader's permanent brown pre-dawn glow; the ridges
//!   then turn darker than the sky and stay visible as silhouettes;
//! - the sun disk keeps a fixed warm colour; only the sky is luminance-capped;
//! - the two hill ridges are taller, so they read as mountains on a 416 px round screen.
//! Colours are recomputed only when the elevation moves by 0.25 degrees (every few
//! minutes); each frame only draws rectangles, two circles and two polygons.
class SkyRenderer {

    const HORIZON_SH = -0.18;      // horizon height in shader units
    const HORIZON_F = 0.798;       // horizon line position, fraction of the height (332 / 416)
    const INTENSITY = 0.6;         // GFX_INTENSITY
    const READABILITY = 0.7;       // GFX_READABILITY
    const KEY_STEP = 8;            // rows between two evaluations of the sky model

    // Shader palette (display space, 0..1)
    const PRIMARY   = [1.0, 0.702, 0.2784] as Array<Float>;     // gold
    const SECONDARY = [0.0549, 0.102, 0.2275] as Array<Float>;  // night blue
    const ACCENT    = [1.0, 0.4353, 0.3804] as Array<Float>;    // coral
    const BACKDROP  = [0.0431, 0.0392, 0.0627] as Array<Float>; // GFX_BACKGROUND
    const DAY_TOP   = [0.35, 0.55, 0.85] as Array<Float>;
    const HILL_DARK = [0.05, 0.05, 0.1] as Array<Float>;
    const HILL_LIT  = [0.15, 0.1, 0.15] as Array<Float>;
    // Deep night: a faint airglow stays at the horizon and the ridges turn darker
    // than the sky, so the mountains read as silhouettes at any hour.
    const NIGHT_HORIZON = [0.10, 0.11, 0.21] as Array<Float>;
    const FAR_NIGHT  = [0.03, 0.03, 0.05] as Array<Float>;
    const NEAR_NIGHT = [0.012, 0.012, 0.02] as Array<Float>;

    private var _w as Number;
    private var _h as Number;
    private var _horizonY as Number;
    private var _trackX0 as Number;
    private var _trackX1 as Number;
    private var _sunR as Number;
    private var _haloR as Number;

    private var _rowColors as Array<Number>;
    private var _hillFar as Array<Graphics.Point2D>;
    private var _hillNear as Array<Graphics.Point2D>;
    private var _hillFarColor as Number = 0;
    private var _hillNearColor as Number = 0;

    private var _sunX as Number = 0;
    private var _sunY as Number = 0;
    private var _haloColor as Number = 0;

    private var _lastElevation as Float = -999.0;
    // MIP screens (fenix 7, Forerunner 255/955, Enduro) show 64 colours: a
    // gradient sky turns into flat blocks there, so they get a black sky with
    // the mountain silhouettes and the sun only.
    private var _mip as Boolean = false;
    private var _lastSunX as Number = -1;

    function initialize(l as LayoutManager) {
        var ds = System.getDeviceSettings();
        _mip = (ds has :requiresBurnInProtection) && !ds.requiresBurnInProtection;
        _w = l.width;
        _h = l.height;
        _horizonY = l.horizonY;
        _trackX0 = l.sunTrackX0;
        _trackX1 = l.sunTrackX1;
        _sunR = l.px(6);
        _haloR = l.px(12);

        _rowColors = new Array<Number>[_h];
        for (var i = 0; i < _h; i++) {
            _rowColors[i] = Palette.BG;
        }
        // Ridges: base below the horizon line, peaks up to amp above the base.
        _hillFar = buildHill(0.06, 0.085, 3.0, 3.0);
        _hillNear = buildHill(0.13, 0.09, 5.0, 40.0);
    }

    //! Recomputes colours when the sun moved enough to be visible.
    //! elevation in degrees, dayFraction 0 at sunrise .. 1 at sunset.
    function update(elevation as Float, dayFraction as Float) as Void {
        var f = dayFraction;
        if (f < 0.0) { f = 0.0; }
        if (f > 1.0) { f = 1.0; }
        var sunX = _trackX0 + (f * (_trackX1 - _trackX0)).toNumber();
        if ((elevation - _lastElevation).abs() < 0.25 && (sunX - _lastSunX).abs() < 2) {
            return;
        }
        _lastElevation = elevation;
        _lastSunX = sunX;

        var sunY = HORIZON_SH + 0.02 * elevation;
        var warm = smooth(-0.4, 0.1, sunY);
        var top = mix(SECONDARY, DAY_TOP, smooth(0.0, 0.25, sunY));
        var low = mix(scale(ACCENT, 0.4), PRIMARY, warm);
        var night = smooth(-16.0, -6.0, elevation);   // 0 deep night .. 1 twilight and day
        var shift = HORIZON_SH - (0.5 - HORIZON_F);    // our y -> shader y

        // The shader model is evaluated only every KEY_STEP rows (it is smooth at
        // this scale); rows in between are interpolated linearly. This keeps one
        // update at about 53 model evaluations instead of 416, far from the
        // watchdog limit.
        var keys = new Array<Array<Float>>[(_h / KEY_STEP) + 2];
        for (var k = 0; k < keys.size(); k++) {
            var ky = k * KEY_STEP;
            var kpy = (_h / 2.0 - (ky + 0.5)) / _h + shift;
            keys[k] = compose(skyAt(kpy.toFloat(), low, top, sunY, warm, night));
        }

        // Rows, dithered to RGB565 with 1-D error diffusion
        var errR = 0.0;
        var errG = 0.0;
        var errB = 0.0;
        for (var y = 0; y < _h; y++) {
            var k0 = y / KEY_STEP;
            var c = mix(keys[k0], keys[k0 + 1], ((y % KEY_STEP) / (KEY_STEP * 1.0)).toFloat());
            var r = c[0] * 255.0 + errR;
            var g = c[1] * 255.0 + errG;
            var b = c[2] * 255.0 + errB;
            var qr = quantize(r, 8.2258);
            var qg = quantize(g, 4.0476);
            var qb = quantize(b, 8.2258);
            errR = r - qr;
            errG = g - qg;
            errB = b - qb;
            _rowColors[y] = (qr.toNumber() << 16) | (qg.toNumber() << 8) | qb.toNumber();
        }

        // Sun: x by daylight fraction, height by elevation, capped below the slots
        var lift = 0.02 * elevation;
        if (lift > 0.0) { lift = 0.0; }      // the sun rests on the ridge, under the icons
        if (lift < -0.06) { lift = -0.06; }
        _sunX = sunX;
        _sunY = _horizonY - (lift * _h).toNumber();
        var behind = compose(skyAt((_h / 2.0 - _sunY) / _h + shift, low, top, sunY, warm, night));
        var t = 0.35 * night;
        _haloColor = toColor([
            (behind[0] + (1.0 - behind[0]) * t).toFloat(),
            (behind[1] + (0.906 - behind[1]) * t).toFloat(),
            (behind[2] + (0.690 - behind[2]) * t).toFloat()] as Array<Float>);

        _hillFarColor = toColor(mix(FAR_NIGHT, compose(mix(HILL_DARK, HILL_LIT, warm)), night));
        _hillNearColor = toColor(mix(NEAR_NIGHT, compose(HILL_DARK), night));
    }

    //! Draws the full background: sky rows (equal neighbours merged), sun, ridges.
    function draw(dc as Dc) as Void {
        if (_mip) {
            drawMip(dc);
            return;
        }
        var start = 0;
        for (var r = 1; r <= _h; r++) {
            if (r == _h || _rowColors[r] != _rowColors[start]) {
                var c = _rowColors[start];
                dc.setColor(c, c);
                dc.fillRectangle(0, start, _w, r - start);
                start = r;
            }
        }

        // The sun is drawn before the ridges, so it rises from behind the mountains.
        dc.setColor(_haloColor, Graphics.COLOR_TRANSPARENT);
        dc.fillCircle(_sunX, _sunY, _haloR);
        dc.setColor(Palette.SUN, Graphics.COLOR_TRANSPARENT);
        dc.fillCircle(_sunX, _sunY, _sunR);

        dc.setColor(_hillFarColor, Graphics.COLOR_TRANSPARENT);
        dc.fillPolygon(_hillFar);
        dc.setColor(_hillNearColor, Graphics.COLOR_TRANSPARENT);
        dc.fillPolygon(_hillNear);
    }

    // ---------------------------------------------------------------- model

    //! Shader sky colour at height py, before luminance capping.
    private function skyAt(py as Float, low as Array<Float>, top as Array<Float>,
                           sunY as Float, warm as Float, night as Float) as Array<Float> {
        var c = mix(low, top, smooth(HORIZON_SH, 0.5, py));
        var glow = 0.3 * expf(-2.0 * (py - sunY).abs()) * warm;
        c = add(c, scale(PRIMARY, glow));
        var nightSky = mix(NIGHT_HORIZON, scale(SECONDARY, 0.55), smooth(HORIZON_SH, 0.5, py));
        return mix(nightSky, c, night);
    }

    //! Ridge polygon sampled every 8 px (53 points + 2 corners, under the 64 limit).
    private function buildHill(base as Float, amp as Float, freq as Float,
                               seed as Float) as Array<Graphics.Point2D> {
        var pts = [] as Array<Graphics.Point2D>;
        var x = 0;
        while (true) {
            var px = (x - _w / 2.0) / _w;
            var top = _horizonY + (base * _h).toNumber() - (amp * fbm(px * freq + seed) * _h).toNumber();
            pts.add([x, top]);
            if (x >= _w) {
                break;
            }
            x += 8;
            if (x > _w) {
                x = _w;
            }
        }
        pts.add([_w, _h]);
        pts.add([0, _h]);
        return pts;
    }

    // ------------------------------------------------------------- colour math

    //! gfx_readable + gfx_compose: cap luminance, then mix with the backdrop.
    private function compose(c as Array<Float>) as Array<Float> {
        return mix(BACKDROP, readable(c), INTENSITY);
    }

    //! Soft luminance cap for light text on a dark theme (shader gfx_readable).
    private function readable(c as Array<Float>) as Array<Float> {
        var l = 0.2126 * c[0] + 0.7152 * c[1] + 0.0722 * c[2];
        var cap = 1.0 + (0.3 - 1.0) * READABILITY;
        var knee = 0.6 * cap;
        if (l <= knee) {
            return c;
        }
        var l2 = knee + (cap - knee) * (1.0 - expf(-(l - knee) / (cap - knee)));
        var s = l2 / l;
        var d0 = c[0] * s;
        var d1 = c[1] * s;
        var d2 = c[2] * s;
        var m = d0;
        if (d1 > m) { m = d1; }
        if (d2 > m) { m = d2; }
        if (m < 0.0001) { m = 0.0001; }
        var p = 1.0 + 2.0 * (1.0 - s);
        return [(m * Math.pow(d0 / m, p)).toFloat(),
                (m * Math.pow(d1 / m, p)).toFloat(),
                (m * Math.pow(d2 / m, p)).toFloat()] as Array<Float>;
    }

    private function smooth(a as Float, b as Float, x as Float) as Float {
        var t = (x - a) / (b - a);
        if (t < 0.0) { t = 0.0; }
        if (t > 1.0) { t = 1.0; }
        return (t * t * (3.0 - 2.0 * t)).toFloat();
    }

    private function mix(a as Array<Float>, b as Array<Float>, t as Float) as Array<Float> {
        return [(a[0] + (b[0] - a[0]) * t).toFloat(),
                (a[1] + (b[1] - a[1]) * t).toFloat(),
                (a[2] + (b[2] - a[2]) * t).toFloat()] as Array<Float>;
    }

    private function add(a as Array<Float>, b as Array<Float>) as Array<Float> {
        return [(a[0] + b[0]).toFloat(), (a[1] + b[1]).toFloat(), (a[2] + b[2]).toFloat()] as Array<Float>;
    }

    private function scale(a as Array<Float>, k as Numeric) as Array<Float> {
        return [(a[0] * k).toFloat(), (a[1] * k).toFloat(), (a[2] * k).toFloat()] as Array<Float>;
    }

    private function toColor(c as Array<Float>) as Number {
        return (channel(c[0]) << 16) | (channel(c[1]) << 8) | channel(c[2]);
    }

    private function channel(v as Float) as Number {
        var n = (v * 255.0 + 0.5).toNumber();
        if (n < 0) { return 0; }
        if (n > 255) { return 255; }
        return n;
    }

    //! Rounds v to the nearest multiple of step, clamped to 0..255.
    private function quantize(v as Float, step as Float) as Float {
        if (v <= 0.0) {
            return 0.0;
        }
        var q = ((v / step + 0.5).toNumber() * step).toFloat();
        if (q > 255.0) {
            return 255.0;
        }
        return q;
    }

    // ------------------------------------------------------------------ noise

    //! Sine-free hash (Hoskins), as in the shader.
    private function hash(p as Float) as Float {
        p = fract(p * 0.1031);
        p = p * (p + 33.33);
        p = p * (p + p);
        return fract(p);
    }

    //! 1-D value noise with quintic interpolation.
    private function noise(x as Float) as Float {
        var i = Math.floor(x).toFloat();
        var f = x - i;
        var u = f * f * f * (f * (f * 6.0 - 15.0) + 10.0);
        var a = hash(i);
        return (a + (hash(i + 1.0) - a) * u).toFloat();
    }

    //! Five-octave fbm normalised to 0..1.
    private function fbm(x as Float) as Float {
        var s = 0.0;
        var amp = 0.5;
        for (var i = 0; i < 5; i++) {
            s += amp * noise(x);
            x = (x * 2.02 + 17.1).toFloat();
            amp *= 0.5;
        }
        return (s / (1.0 - 0.03125)).toFloat();
    }

    private function fract(v as Float) as Float {
        return (v - Math.floor(v)).toFloat();
    }

    //! e^x. Toybox.Math has no exp(), so it is built from pow() and the constant E.
    private function expf(x as Numeric) as Float {
        return Math.pow(Math.E, x).toFloat();
    }

    //! 64-colour screens: black sky, the sun (by day), two dark ridges.
    private function drawMip(dc as Dc) as Void {
        dc.setColor(Graphics.COLOR_BLACK, Graphics.COLOR_BLACK);
        dc.clear();
        if (_sunY < _horizonY) {
            dc.setColor(Palette.SUN_MIP, Graphics.COLOR_TRANSPARENT);
            dc.fillCircle(_sunX, _sunY, _sunR);
        }
        dc.setColor(Palette.HILL_FAR_MIP, Graphics.COLOR_TRANSPARENT);
        dc.fillPolygon(_hillFar);
        dc.setColor(Palette.HILL_NEAR_MIP, Graphics.COLOR_TRANSPARENT);
        dc.fillPolygon(_hillNear);
    }
}
