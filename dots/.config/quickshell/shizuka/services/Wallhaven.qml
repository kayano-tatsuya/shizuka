pragma Singleton
pragma ComponentBehavior: Bound

import qs.modules.common
import qs.modules.common.functions
import QtQuick
import Quickshell
import Quickshell.Io

// Wallhaven — online wallpaper search/download for the AE-style switcher.
//
// Thin QML wrapper over scripts/wallpaper/wallhaven.py (search + download),
// mirroring the structured-JSON-to-stdout / errors-to-stderr contract the
// script documents. Results are normalized {id, preview, large, full,
// resolution, ratio, purity, category, file_type, page_url} items; the switcher
// renders them in the same masonry strip as local wallpapers.
//
// Applying a result downloads the full-res file into
// <library>/wallhaven/<id>.<ext> and then reuses the ordinary local apply
// pipeline, so a downloaded wallpaper behaves exactly like a local one.
//
// NSFW gating: Wallhaven only serves Sketchy/NSFW to authenticated keys, and
// shizuka only wants that content when its own weeb policy is on. purity is
// therefore clamped to SFW unless both an API key exists AND
// Config.options.policies.weeb !== 0.
Singleton {
    id: root

    readonly property string scriptPath: `${FileUtils.trimFileProtocol(Directories.scriptPath)}/wallpaper/wallhaven.py`
    readonly property string apiKey: KeyringStorage.keyringData?.apiKeys?.wallhaven ?? ""
    readonly property bool hasApiKey: root.apiKey.length > 0
    readonly property bool nsfwAllowed: root.hasApiKey && Config.options.policies.weeb !== 0

    // Wallhaven purity is cumulative: sfw ⊂ sketchy ⊂ nsfw.
    readonly property var purityMap: ({ "sfw": "100", "sketchy": "110", "nsfw": "111" })
    // general | anime | people, as independent bits.
    readonly property var categoryBits: ({ "general": 0, "anime": 1, "people": 2 })

    // ---- filters (persisted via Config.options.wallpaperSelector.wallhaven) ----
    property string query: Config.options.wallpaperSelector.wallhaven.q ?? ""
    property string categories: Config.options.wallpaperSelector.wallhaven.categories || "111"
    property string purityLvl: "sfw"
    property string sorting: Config.options.wallpaperSelector.wallhaven.sorting || "date_added"
    property string order: Config.options.wallpaperSelector.wallhaven.order || "desc"
    property string topRange: Config.options.wallpaperSelector.wallhaven.topRange || "1M"
    property string atleast: Config.options.wallpaperSelector.wallhaven.atleast || ""
    property string ratios: Config.options.wallpaperSelector.wallhaven.ratios || ""

    // ---- request state ----
    property int page: 1
    property bool loading: false
    property bool appending: false
    property string error: ""
    property var results: []
    property int lastPage: 1
    property int total: 0
    property string _seed: ""
    property string downloadingId: ""

    readonly property var sortingOptions: [
        { value: "date_added", label: Translation.tr("Newest") },
        { value: "relevance", label: Translation.tr("Relevance") },
        { value: "random", label: Translation.tr("Random") },
        { value: "views", label: Translation.tr("Views") },
        { value: "favorites", label: Translation.tr("Favorites") },
        { value: "toplist", label: Translation.tr("Top list") }
    ]

    readonly property var resolutionOptions: [
        { value: "", label: Translation.tr("Any") },
        { value: "1920x1080", label: "1080p" },
        { value: "2560x1440", label: "1440p" },
        { value: "3840x2160", label: "4K" }
    ]

    signal searched()

    function purityValue() {
        return root.purityMap[root.purityLvl] ?? "100";
    }

    // Force SFW whenever the gate is closed, even if a level was set earlier.
    function clampPurity() {
        if (!root.nsfwAllowed && root.purityLvl !== "sfw")
            root.purityLvl = "sfw";
    }

    function categoryBitOn(name) {
        const bit = root.categoryBits[name];
        if (bit === undefined || root.categories.length !== 3)
            return false;
        return root.categories[bit] === "1";
    }

    function toggleCategory(name) {
        const bit = root.categoryBits[name];
        if (bit === undefined || root.categories.length !== 3)
            return;
        const chars = root.categories.split("");
        chars[bit] = chars[bit] === "1" ? "0" : "1";
        const next = chars.join("");
        // Never leave a zero-bit search (Wallhaven 400s).
        if (next === "000")
            return;
        root.categories = next;
    }

    function setSorting(value) {
        root.sorting = value;
        root.search();
    }

    function search() {
        // Dedupe simultaneous auto-searches (one selector body per monitor).
        if (root.loading)
            return;
        root.page = 1;
        root._seed = "";
        root.appending = false;
        root._fetch();
    }

    function nextPage() {
        if (root.loading || root.appending || root.page >= root.lastPage)
            return;
        root.appending = true;
        root.page += 1;
        root._fetch();
    }

    function prevPage() {
        if (root.loading || root.page <= 1)
            return;
        root.appending = false;
        root.page -= 1;
        root._fetch();
    }

    function _fetch() {
        root.clampPurity();
        root.loading = true;
        const args = ["python3", root.scriptPath, "--search",
            "--categories", root.categories,
            "--purity", root.purityValue(),
            "--sorting", root.sorting,
            "--order", root.order,
            "--page", String(root.page)];
        if (root.query.length > 0)
            args.push("--q", root.query);
        if (root.sorting === "toplist" && root.topRange.length > 0)
            args.push("--top-range", root.topRange);
        if (root.sorting === "random" && root._seed.length > 0)
            args.push("--seed", root._seed);
        if (root.atleast.length > 0)
            args.push("--atleast", root.atleast);
        if (root.ratios.length > 0)
            args.push("--ratios", root.ratios);
        if (root.apiKey.length > 0)
            args.push("--api-key", root.apiKey);
        searchProc.command = args;
        searchProc.running = true;
    }

    property Process searchProc: Process {
        stdout: StdioCollector {
            onStreamFinished: {
                let payload;
                try {
                    payload = JSON.parse(text);
                } catch (e) {
                    // Non-zero exits print their error to stderr, handled below.
                    return;
                }
                const data = payload.data || [];
                root.results = root.appending ? root.results.concat(data) : data;
                const meta = payload.meta || {};
                root.lastPage = meta.last_page || root.page;
                root.total = meta.total || data.length;
                if (root.sorting === "random" && root._seed.length === 0 && meta.seed)
                    root._seed = String(meta.seed);
                root.error = "";
                root.searched();
            }
        }
        stderr: StdioCollector {
            onStreamFinished: {
                const t = text.trim();
                if (t.length === 0)
                    return;
                try {
                    root.error = JSON.parse(t.split("\n").pop()).message || t;
                } catch (e) {
                    root.error = t;
                }
            }
        }
        onExited: {
            root.loading = false;
            root.appending = false;
        }
    }

    function _extFor(item) {
        const ft = String(item.file_type || "").toLowerCase();
        if (ft.indexOf("png") >= 0)
            return "png";
        if (ft.indexOf("webp") >= 0)
            return "webp";
        if (ft.indexOf("gif") >= 0)
            return "gif";
        return "jpg";
    }

    // download(item, onDone(path), onError(message))
    property var _onDone: null
    property var _onError: null
    property string _dest: ""

    function download(item, onDone, onError) {
        if (!item || !item.id)
            return;
        const dest = `${WallpaperLibrary.wallhavenDir}/${item.id}.${root._extFor(item)}`;
        root._dest = dest;
        root._onDone = onDone || null;
        root._onError = onError || null;
        root.downloadingId = item.id;
        const args = ["python3", root.scriptPath, "--download", item.id, "--dest", dest];
        if (item.full && item.full.length > 0)
            args.push("--full-url", item.full);
        if (root.apiKey.length > 0)
            args.push("--api-key", root.apiKey);
        downloadProc.command = args;
        downloadProc.running = true;
    }

    property Process downloadProc: Process {
        stderr: StdioCollector {
            onStreamFinished: {
                const t = text.trim();
                if (t.length === 0 || !root._onError)
                    return;
                try {
                    root._onError(JSON.parse(t.split("\n").pop()).message || t);
                } catch (e) {
                    root._onError(t);
                }
            }
        }
        onExited: (code, status) => {
            root.downloadingId = "";
            if (code === 0 && root._onDone)
                root._onDone(root._dest);
            root._onDone = null;
            root._onError = null;
        }
    }
}
