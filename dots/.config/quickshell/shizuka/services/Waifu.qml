pragma Singleton

import qs.modules.common
import qs.services
import Quickshell
import QtQuick

/**
 * Random-waifu source for the right sidebar's waifu banner.
 *
 * Providers are reused from `Booru.providers` (endpoint + response mapper): a
 * provider declared there is usable here for free, so adding a new image host
 * stays a one-place change. This service only asks for a page of images and
 * keeps one at random, exposing it declaratively so the widget stays dumb.
 */
Singleton {
    id: root

    // ---- Tunables (Config.options.sidebar.waifu) ----
    readonly property bool enabled: Config.options?.sidebar?.waifu?.enable ?? true
    readonly property string provider: Config.options?.sidebar?.waifu?.provider ?? "waifu.im"
    // Auto-refresh period in seconds; 0 = fetch on demand only.
    readonly property int refreshInterval: Config.options?.sidebar?.waifu?.refreshInterval ?? 0

    // The image on display (an entry from Booru's mapper), or null until the
    // first successful fetch.
    property var current: null
    property bool loading: false
    property string errorMessage: ""

    // Provider the current image was fetched with. Stays empty until the first
    // fetch starts, which is how the provider watcher below ignores the binding
    // churn that happens while the config is still loading.
    property string activeProvider: ""

    // ---- Persistence -----------------------------------------------------

    // The stored waifu (a mapped image object) or null when none has been
    // pinned. Kept as a one-element list in Persistent (see its comment).
    function pinnedImage() {
        const list = Persistent.states.waifu.pinned ?? [];
        return list.length > 0 ? list[0] : null;
    }

    function _persist(image) {
        if (!image) return;
        try {
            // Deep-clone so the adapter stores plain JSON instead of a live
            // object that could keep changing under it.
            Persistent.states.waifu.pinned = [JSON.parse(JSON.stringify(image))];
        } catch (e) {
            console.log("[Waifu] Could not persist waifu: " + e);
        }
    }

    /**
     * Pin the given image as the sidebar waifu and show it immediately. This is
     * what the booru viewer's "set as waifu" action calls.
     */
    function setWaifu(image) {
        if (!image) return;
        root.current = image;
        root._persist(image);
    }

    function clearWaifu() {
        root.current = null;
        Persistent.states.waifu.pinned = [];
    }

    /**
     * True when `image` is the waifu currently on display. Compares by file URL
     * when both sides have one (ids are only unique within a provider), and
     * falls back to the id otherwise.
     */
    function isCurrent(image) {
        const w = root.current;
        if (!w || !image) return false;
        if (w.file_url && image.file_url) return String(w.file_url) === String(image.file_url);
        return String(w.id) === String(image.id);
    }

    /**
     * Show the pinned waifu once Persistent is ready, or fetch a random one if
     * nothing has ever been pinned. Safe to call repeatedly and only ever acts
     * on an empty banner, so callers (the widget's onVisible, a config change)
     * cannot race a fetch over an image that is already showing.
     */
    function ensureLoaded() {
        if (root.current !== null || root.loading || !Persistent.ready) return;
        const pinned = root.pinnedImage();
        if (pinned) {
            root.current = pinned;
            return;
        }
        if (root.enabled) root.refresh();
    }

    /**
     * Fetch a fresh batch and keep one at random. Calls while a request is in
     * flight are ignored so mashing "refresh" can neither queue requests nor
     * trip the providers' rate limits.
     */
    function refresh() {
        if (root.loading) return;

        const provider = root.provider;
        let url = "";
        try {
            // SFW only: the sidebar is always on screen, so gating would be
            // awkward and this is what people expect from a sidebar waifu.
            url = Booru.constructRequestUrl([], false, 20, 1, provider);
        } catch (e) {
            root.errorMessage = String(e);
            console.log("[Waifu] Could not build request for '" + provider + "': " + e);
            return;
        }

        root.activeProvider = provider;
        root.loading = true;
        root.errorMessage = "";

        const xhr = new XMLHttpRequest();
        xhr.open("GET", url);
        xhr.onreadystatechange = function() {
            if (xhr.readyState !== XMLHttpRequest.DONE) return;
            root.loading = false;
            if (xhr.status !== 200) {
                root.errorMessage = "HTTP " + xhr.status;
                console.log("[Waifu] Request failed (" + xhr.status + "): " + url);
                return;
            }
            try {
                const p = Booru.providers[provider];
                const images = p.manualParseFunc
                    ? p.manualParseFunc(xhr.responseText)
                    : p.mapFunc(JSON.parse(xhr.responseText));
                if (!images || images.length === 0) {
                    root.errorMessage = Translation.tr("No image returned");
                    return;
                }
                root.current = images[Math.floor(Math.random() * images.length)];
                root._persist(root.current);
            } catch (e) {
                root.errorMessage = String(e);
                console.log("[Waifu] Failed to parse response: " + e);
            }
        };
        try {
            xhr.send();
        } catch (e) {
            root.loading = false;
            root.errorMessage = String(e);
            console.log("[Waifu] Could not send request: " + e);
        }
    }

    // Restore the pinned waifu (or fetch a first one) once Persistent is ready.
    // Waiting for readiness — rather than fetching blindly on completion — is
    // what keeps the banner static across reloads: the async states file is not
    // guaranteed to have loaded by Component.onCompleted.
    Component.onCompleted: root.ensureLoaded()

    Connections {
        target: Persistent
        function onReadyChanged() { root.ensureLoaded(); }
    }

    onEnabledChanged: if (root.enabled) root.ensureLoaded()

    // A provider switch (config edit) should show a fresh image. Guarded so the
    // startup churn — where `provider` is read before the config has loaded —
    // cannot fire a second request (and so cannot clobber a restored waifu).
    onProviderChanged: {
        if (root.activeProvider === "" || root.activeProvider === root.provider) return;
        root.refresh();
    }

    // Optional rotation. `Math.max` guards against a 0/negative interval
    // becoming a tight loop.
    Timer {
        interval: Math.max(1, root.refreshInterval) * 1000
        running: root.enabled && root.refreshInterval > 0
        repeat: true
        onTriggered: root.refresh()
    }
}
