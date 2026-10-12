pragma Singleton
pragma ComponentBehavior: Bound

import qs.modules.common
import qs.modules.common.functions
import QtQuick
import Quickshell
import Quickshell.Io

// WallpaperLibrary — shared store for the AE-style wallpaper switcher.
//
// Owns the heavy/shared state that must not be refetched per open:
//   - the local category map  { "<relative dir>": [abs paths] } from
//     scripts/wallpaper/get-wallpapers.sh (one run at boot, shared by every
//     monitor),
//   - the video first-frame thumb manifest (gen-video-thumbs.sh),
//   - the decoded-aspect cache used by the masonry layout,
//   - the per-workspace wallpaper map ("<monitor>::<wsId>" -> path), persisted
//     to the state dir so it survives restarts.
//
// WallpaperSwitcherBody binds read-only and delegates helpers here;
// Background.qml reads the per-workspace map to render the active workspace's
// wallpaper. Nothing here renders or themes — apply goes through switchwall.sh.
Singleton {
    id: root

    readonly property string _scripts: FileUtils.trimFileProtocol(Directories.scriptPath)
    readonly property string listScript: `${root._scripts}/wallpaper/get-wallpapers.sh`
    readonly property string thumbScript: `${root._scripts}/wallpaper/gen-video-thumbs.sh`
    readonly property string workspaceMapDir: FileUtils.trimFileProtocol(`${Directories.state}/user/generated/wallpaper`)
    readonly property string workspaceMapPath: `${root.workspaceMapDir}/workspace-wallpapers.json`

    // Local library root (must match get-wallpapers.sh's default); online
    // downloads (wallhaven) land in the wallhaven subcategory and then ride the
    // ordinary local apply pipeline.
    readonly property string libraryRoot: FileUtils.trimFileProtocol(`${Directories.pictures}/Wallpapers`)
    readonly property string wallhavenDir: `${root.libraryRoot}/wallhaven`

    // category -> [paths]; reassigned, never mutated (masonry recompute).
    property var wallpapers: ({})
    property string _lastWallpapersJson: ""

    // video path -> thumb path manifest (merged incrementally).
    property var thumbMap: ({})

    // decoded-aspect cache (path -> w/h); batched adopt via _pendingAspect.
    property var localAspect: ({})
    property var _pendingAspect: ({})
    property bool _thumbPending: false
    property bool _started: false

    // "<monitor>::<wsId>" -> path, persisted.
    property var workspaceMap: ({})
    property bool workspaceMapLoaded: false

    function isVideoFile(file) {
        return /\.(mp4|webm|mkv|mov)$/i.test(file || "");
    }

    function localAspectOf(path) {
        const r = root.localAspect[path] || 0;
        return r > 0 ? r : 16 / 9;
    }

    function noteLocalAspect(path, ratio) {
        if (!isFinite(ratio) || ratio <= 0)
            return;
        const cur = root.localAspect[path] || root._pendingAspect[path] || 0;
        if (Math.abs(cur - ratio) < 0.01)
            return;
        root._pendingAspect[path] = ratio;
        aspectFlush.restart();
    }

    function thumbFor(path) {
        if (path === undefined || !root.isVideoFile(path))
            return "";
        return root.thumbMap[path] || "";
    }

    // ---------------------------------------------------- per-workspace map
    function wsKey(monitor, wsId) {
        return `${monitor}::${String(wsId)}`;
    }

    function workspaceWallpaper(monitor, wsId) {
        if (!monitor || wsId === undefined || wsId === null)
            return "";
        return root.workspaceMap[root.wsKey(monitor, wsId)] || "";
    }

    function setWorkspaceWallpaper(monitor, wsId, path) {
        if (!monitor || wsId === undefined || wsId === null)
            return;
        const next = Object.assign({}, root.workspaceMap);
        const key = root.wsKey(monitor, wsId);
        if (!path)
            delete next[key];
        else
            next[key] = path;
        root.workspaceMap = next;
        root._persistWorkspaceMap();
    }

    function _persistWorkspaceMap() {
        const jsonStr = JSON.stringify(root.workspaceMap, null, 2);
        // Heredoc (quoted delimiter) keeps the JSON literal — same belt-and-
        // suspenders as Wallpapers.saveCustomOrder.
        Quickshell.execDetached(["bash", "-c",
            `mkdir -p '${root.workspaceMapDir}' && cat << 'SHIZUKA_WP_EOF' > '${root.workspaceMapPath}.tmp' && mv '${root.workspaceMapPath}.tmp' '${root.workspaceMapPath}'\n${jsonStr}\nSHIZUKA_WP_EOF`]);
    }

    // ------------------------------------------------------------ fetching
    function start() {
        if (root._started)
            return;
        root._started = true;
        root.refresh();
    }

    function refresh() {
        fetchProc.running = true;
    }

    property Process fetchProc: Process {
        command: ["bash", root.listScript]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    // Skip no-change adoptions: every reassign rebuilds the
                    // masonry + re-decodes all tiles (visible flicker).
                    if (text === root._lastWallpapersJson)
                        return;
                    root._lastWallpapersJson = text;
                    root.wallpapers = JSON.parse(text);
                    root.runThumbGen();
                } catch (e) {
                    console.warn("[WallpaperLibrary] fetching wallpapers", e);
                }
            }
        }
    }

    property Timer aspectFlush: Timer {
        interval: 250
        onTriggered: {
            if (Object.keys(root._pendingAspect).length === 0)
                return;
            root.localAspect = Object.assign({}, root.localAspect, root._pendingAspect);
            root._pendingAspect = {};
        }
    }

    // Background thumb run over every known local video (fresh ones skip on
    // mtime inside the script, so re-runs are cheap). Single-flight: a fetch
    // storm while a run is active re-runs once on exit.
    property Process thumbProc: Process {
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const m = JSON.parse(text);
                    if (m && typeof m === "object")
                        root.thumbMap = Object.assign({}, root.thumbMap, m);
                } catch (e) {
                    console.warn("[WallpaperLibrary] thumb manifest parse failed", e);
                }
            }
        }
        onExited: {
            if (root._thumbPending) {
                root._thumbPending = false;
                root.runThumbGen();
            }
        }
    }

    function runThumbGen() {
        if (thumbProc.running) {
            root._thumbPending = true;
            return;
        }
        const vids = [];
        const cats = root.wallpapers || {};
        for (const k in cats) {
            const list = cats[k] || [];
            for (let i = 0; i < list.length; i++)
                if (root.isVideoFile(list[i]) && !root.thumbMap[list[i]])
                    vids.push(list[i]);
        }
        if (vids.length === 0)
            return;
        thumbProc.command = ["bash", root.thumbScript].concat(vids);
        thumbProc.running = true;
    }

    // Read the workspace map through a shell guard so a first run (file not yet
    // written) is silent instead of a FileView "Read failed" warning.
    property Process workspaceLoadProc: Process {
        command: ["bash", "-c",
            `[ -f '${root.workspaceMapPath}' ] && cat '${root.workspaceMapPath}' || echo '{}'`]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    root.workspaceMap = JSON.parse(text) || {};
                } catch (e) {
                    console.warn("[WallpaperLibrary] parsing workspace map", e);
                    root.workspaceMap = {};
                }
                root.workspaceMapLoaded = true;
            }
        }
        onExited: {
            if (!root.workspaceMapLoaded)
                root.workspaceMapLoaded = true;
        }
    }

    Component.onCompleted: {
        workspaceLoadProc.running = true;
        root.start();
    }
}
