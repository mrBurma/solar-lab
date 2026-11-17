import Toybox.Lang;

//! Tracks the watch face power state and the burn-in protection offset.
//! High power: about 10 s after a wrist gesture, onUpdate runs every second.
//! Low power (always-on): onUpdate runs once per minute.
class PowerManager {

    private var _lowPower as Boolean = false;

    // Burn-in protection orbit: the AOD content moves one step per minute,
    // so no pixel stays lit in the same position for long.
    private var _orbitX as Array<Number> = [0, 6, 10, 4, -4, -10, -6, 0] as Array<Number>;
    private var _orbitY as Array<Number> = [0, -4, 2, 8, 8, 2, -4, -8] as Array<Number>;

    function initialize() {
    }

    function setLowPower(lowPower as Boolean) as Void {
        _lowPower = lowPower;
    }

    function isLowPower() as Boolean {
        return _lowPower;
    }

    //! Seconds are only drawn in high-power mode; AMOLED watch faces
    //! cannot use onPartialUpdate for per-second updates in low power.
    function showSeconds() as Boolean {
        return !_lowPower;
    }

    //! Horizontal AOD offset in pixels for the given minute.
    function offsetX(minute as Number) as Number {
        return _orbitX[minute % _orbitX.size()];
    }

    //! Vertical AOD offset in pixels for the given minute.
    function offsetY(minute as Number) as Number {
        return _orbitY[minute % _orbitY.size()];
    }
}
