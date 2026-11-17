import Toybox.Lang;
import Toybox.WatchUi;

//! Localised UI text. Strings live in resources/strings (English, the default)
//! and resources-rus/strings (Russian); Connect IQ loads the set that matches the
//! watch's system language, so the face follows Settings > System > Language.
//! Each string is loaded once and cached: the advice and reason lines are
//! rebuilt every few seconds while the screen is awake.
module Tr {

    var _cache as Dictionary<ResourceId, String> = {} as Dictionary<ResourceId, String>;

    //! The string for a resource id, e.g. Tr.s(Rez.Strings.AdvSleep).
    function s(id as ResourceId) as String {
        var v = _cache[id];
        if (v == null) {
            v = WatchUi.loadResource(id) as String;
            _cache[id] = v;
        }
        return v;
    }

    //! A string with $1$, $2$ slots filled, e.g. Tr.f(Rez.Strings.RsnNight, [54]).
    function f(id as ResourceId, args as Array) as String {
        return Lang.format(s(id), args);
    }

    //! A space-separated list resource split into words ("SUN MON ..." -> [..]).
    function words(id as ResourceId) as Array<String> {
        var out = [] as Array<String>;
        var rest = s(id);
        var i = rest.find(" ");
        while (i != null) {
            out.add(rest.substring(0, i) as String);
            rest = rest.substring(i + 1, null) as String;
            i = rest.find(" ");
        }
        out.add(rest);
        return out;
    }
}
