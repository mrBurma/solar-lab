import Toybox.Application;
import Toybox.Background;
import Toybox.Lang;
import Toybox.System;
import Toybox.Time;
import Toybox.WatchUi;

//! Application entry point. Creates the watch face view and registers the
//! background sentinel (source/background/Sentinel.mc), which the system wakes
//! every 5 minutes even while the screen is off.
(:background)
class SolarLabApp extends Application.AppBase {

    function initialize() {
        AppBase.initialize();
    }

    function onStart(state as Dictionary?) as Void {
    }

    function onStop(state as Dictionary?) as Void {
    }

    //! Entry point of the background process.
    function getServiceDelegate() as [System.ServiceDelegate] {
        return [new Sentinel()];
    }

    //! Returns the watch face view and its touch delegate. Foreground only.
    (:typecheck(disableBackgroundCheck))
    function getInitialView() as [Views] or [Views, InputDelegates] {
        if (Toybox has :Background) {
            Background.registerForTemporalEvent(new Time.Duration(5 * 60));
        }
        var view = new SolarLabView();
        return [view, new SolarLabDelegate(view)];
    }

    //! Called when the user changes settings in Garmin Connect Mobile.
    (:typecheck(disableBackgroundCheck))
    function onSettingsChanged() as Void {
        WatchUi.requestUpdate();
    }
}
