import Toybox.Complications;
import Toybox.Lang;
import Toybox.WatchUi;

//! Touch handling. Touch and hold on a slot opens the native Garmin widget of that
//! metric (Complications.exitTo, API 4.2). There the user finds what a watch face
//! cannot read: HRV status, sleep score, full history graphs.
//! A plain tap is not delivered to watch faces outside the edit mode, so only
//! the long press is used.
class SolarLabDelegate extends WatchUi.WatchFaceDelegate {

    private var _view as SolarLabView;

    function initialize(view as SolarLabView) {
        WatchFaceDelegate.initialize();
        _view = view;
    }

    function onPress(clickEvent as WatchUi.ClickEvent) as Boolean {
        var xy = clickEvent.getCoordinates();
        var kind = _view.slotKindAt(xy[0], xy[1]);
        if (kind < 0) {
            return false;
        }
        var id = _view.health().complicationFor(kind);
        if (id == null) {
            return false;
        }
        try {
            Complications.exitTo(id);
            return true;
        } catch (e) {
            // The complication has no app to open on this device
        }
        return false;
    }
}
