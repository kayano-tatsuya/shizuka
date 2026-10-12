import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import QtQuick
import QtQuick.Controls
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Hyprland

Scope {
    id: root

    // Latch: once the selector has first opened, the heavy PanelWindow + picker
    // body stay alive and are visibility-toggled instead of being torn down.
    // Tile decodes, the decoded-aspect cache and the strip scroll position
    // therefore survive closes, so a reopen no longer rebuilds/re-decodes the
    // masonry (same idiom as SidebarLeft, and ArchEclipse's cached wallpaper
    // island). Memory while closed is bounded by the in-view tiles — the masonry
    // unloads off-screen cells even while the body stays alive.
    property bool primed: false
    property bool reallyOpen: false

    Connections {
        target: GlobalStates
        function onWallpaperSelectorOpenChanged() {
            if (GlobalStates.wallpaperSelectorOpen) {
                closeAnimTimer.stop();
                if (!root.primed) {
                    // First open constructs the window; its Component.onCompleted
                    // performs the slide-in.
                    root.primed = true;
                } else if (wallpaperSelectorLoader.item) {
                    // Reopen: re-snap the body out of view, then slide it in.
                    wallpaperSelectorLoader.item.slideIn();
                }
                root.reallyOpen = true;
            } else {
                closeAnimTimer.restart();
            }
        }
    }

    Timer {
        id: closeAnimTimer
        interval: Appearance.animation.sidebarSlideExit.duration
        onTriggered: root.reallyOpen = false
    }

    Loader {
        id: wallpaperSelectorLoader
        active: root.primed

        sourceComponent: PanelWindow {
            id: panelWindow
            readonly property var monitor: WM.monitorFor(panelWindow.screen)
            property bool monitorIsFocused: WM.compositor === "hyprland"
                ? (Hyprland.focusedMonitor?.name == monitor?.name)
                : (WM.focusedMonitor?.name == monitor?.name)

            // Visibility-toggled after the first open (see root.primed). While
            // false the layer-shell surface is unmapped, so a closed selector
            // costs no compositing/GPU time — only the retained body.
            visible: root.reallyOpen

            exclusionMode: ExclusionMode.Ignore
            WlrLayershell.namespace: "quickshell:wallpaperSelector"
            WlrLayershell.layer: WlrLayer.Overlay
            WlrLayershell.keyboardFocus: WlrKeyboardFocus.OnDemand
            color: "transparent"

            anchors.top: true
            margins {
                top: Config?.options.bar.vertical ? Appearance.sizes.hyprlandGapsOut : Appearance.sizes.barHeight + Appearance.sizes.hyprlandGapsOut
            }

            mask: Region {
                item: content
            }

            implicitWidth: Appearance.sizes.wallpaperSelectorWidth
            // The masonry switcher hugs its content (a 2-row strip needs far
            // less than the full grid height), so only the grid honours the
            // fixed height box. Clamp so an over-tall/empty body can neither
            // collapse nor exceed the configured height.
            implicitHeight: {
                if (Config.options.wallpaperSelector.style !== "switcher")
                    return Appearance.sizes.wallpaperSelectorHeight;
                const body = content.item;
                const h = (body && body.idealHeight > 0)
                    ? body.idealHeight
                    : Appearance.sizes.wallpaperSelectorHeight;
                return Math.max(200, Math.min(h, Appearance.sizes.wallpaperSelectorHeight));
            }

            // The picker body is a Loader so the grid and the AE-style masonry
            // switcher can swap on Config.options.wallpaperSelector.style
            // without either knowing about the other. Slide-in/out lives on the
            // Loader (geometry), so both bodies behave identically.
            function slideIn() {
                content.y = -content.height;
                if (WM.compositor === "niri") {
                    Qt.callLater(() => { Qt.callLater(() => { content.y = 0; }); });
                } else {
                    Qt.callLater(() => { content.y = 0; });
                }
            }

            Component.onCompleted: {
                panelWindow.slideIn();
            }
            // Focus grab tracks visibility, not construction: the window now
            // outlives a close (see root.primed), so it must only dismiss while
            // actually shown.
            onVisibleChanged: {
                if (visible) {
                    GlobalFocusGrab.addDismissable(panelWindow);
                } else {
                    GlobalFocusGrab.removeDismissable(panelWindow);
                }
            }
            Connections {
                target: GlobalFocusGrab
                function onDismissed() {
                    GlobalStates.wallpaperSelectorOpen = false;
                }
            }

            Component {
                id: gridBodyComponent
                WallpaperSelectorContent {}
            }

            Component {
                id: switcherBodyComponent
                WallpaperSwitcherBody {}
            }

            Loader {
                id: content
                width: parent.width
                height: parent.height
                x: 0
                y: 0
                sourceComponent: Config.options.wallpaperSelector.style === "switcher"
                    ? switcherBodyComponent
                    : gridBodyComponent

                Connections {
                    target: GlobalStates
                    function onWallpaperSelectorOpenChanged() {
                        if (!GlobalStates.wallpaperSelectorOpen) {
                            content.y = -content.height;
                        }
                    }
                }

                Behavior on y {
                    NumberAnimation {
                        duration: WM.compositor === "niri"
                            ? Appearance.animation.sidebarSlideEnter.duration
                            : Appearance.animation.sidebarSlideExit.duration
                        easing.type: GlobalStates.wallpaperSelectorOpen
                            ? Appearance.animation.sidebarSlideEnter.type
                            : Appearance.animation.sidebarSlideExit.type
                        easing.bezierCurve: GlobalStates.wallpaperSelectorOpen
                            ? Appearance.animation.sidebarSlideEnter.bezierCurve
                            : Appearance.animation.sidebarSlideExit.bezierCurve
                    }
                }
            }
        }
    }

    function toggleWallpaperSelector() {
        if (Config.options.wallpaperSelector.useSystemFileDialog) {
            Wallpapers.openFallbackPicker(Appearance.m3colors.darkmode);
            return;
        }
        GlobalStates.wallpaperSelectorOpen = !GlobalStates.wallpaperSelectorOpen
    }

    IpcHandler {
        target: "wallpaperSelector"

        function toggle(): void {
            root.toggleWallpaperSelector();
        }

        function random(): void {
            Wallpapers.randomFromCurrentFolder();
        }
    }

    CompositorGlobalShortcut {
        name: "wallpaperSelectorToggle"
        description: "Toggle wallpaper selector"
        onPressed: {
            root.toggleWallpaperSelector();
        }
    }

    CompositorGlobalShortcut {
        name: "wallpaperSelectorRandom"
        description: "Select random wallpaper in current folder"
        onPressed: {
            Wallpapers.randomFromCurrentFolder();
        }
    }
}