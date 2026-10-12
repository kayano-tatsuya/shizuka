pragma Singleton
pragma ComponentBehavior: Bound

import qs.modules.common
import qs.modules.common.functions
import QtQuick
import Quickshell
import Quickshell.Hyprland

// WorkspaceTheming — makes the shell colors follow the focused workspace.
//
// Only active when Config.options.background.perWorkspace.{enable,reTheme} are
// both on. On a (debounced) focused-workspace change it looks up the mapped
// wallpaper for that workspace and re-runs the color engine with
// `switchwall.sh --noswitch --image <path>`, which regenerates the palette from
// the image *without* touching background.wallpaperPath (colors-only path).
//
// Rendering itself lives in Background.qml (workspaceWallpaperPath); this
// singleton only keeps the global palette in sync, so at most one re-theme is
// in flight regardless of how many monitors exist.
//
// Instantiated eagerly from shell.qml — QML singletons are otherwise lazy, so
// without that call this would never run until something referenced it.
Singleton {
    id: root

    readonly property bool active: Config.options.background.perWorkspace.enable
        && Config.options.background.perWorkspace.reTheme

    readonly property string focusedMonitorName: Hyprland.focusedMonitor?.name ?? ""
    readonly property int focusedWorkspaceId: Hyprland.focusedMonitor?.activeWorkspace?.id ?? -1

    // Last "monitor::ws -> path" we themed, so returning to the same workspace
    // (or a monitor refocus with no wallpaper change) does not respawn the script.
    property string _lastKey: ""
    property string _lastPath: ""

    onActiveChanged: if (root.active) root._schedule()
    onFocusedWorkspaceIdChanged: root._schedule()
    onFocusedMonitorNameChanged: root._schedule()

    function _schedule() {
        if (!root.active || root.focusedWorkspaceId <= 0)
            return;
        debounce.restart();
    }

    // Called from shell.qml Component.onCompleted to force instantiation.
    function load() {
        root._schedule();
    }

    Connections {
        target: Config
        function onReadyChanged() {
            if (Config.ready)
                root._schedule();
        }
    }

    function _apply() {
        if (!root.active)
            return;
        // The workspace map loads asynchronously (WallpaperLibrary at startup);
        // retry until it's ready so the first equipped workspace still themes.
        if (!WallpaperLibrary.workspaceMapLoaded) {
            debounce.restart();
            return;
        }
        const mon = root.focusedMonitorName;
        const ws = root.focusedWorkspaceId;
        if (mon.length === 0 || ws <= 0)
            return;
        const path = WallpaperLibrary.workspaceWallpaper(mon, ws);
        if (!path || path.length === 0)
            return;
        const key = `${mon}::${ws}`;
        if (key === root._lastKey && path === root._lastPath)
            return;
        root._lastKey = key;
        root._lastPath = path;
        // Array form: keeps paths containing spaces intact.
        Quickshell.execDetached([Directories.wallpaperSwitchScriptPath, "--noswitch", "--image", path]);
    }

    // Debounce: workspace scrolling can fire a burst of changes.
    Timer {
        id: debounce
        interval: 400
        onTriggered: root._apply()
    }
}
