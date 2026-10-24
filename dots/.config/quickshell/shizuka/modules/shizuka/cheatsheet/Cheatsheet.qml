import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import qs.modules.shizuka.sidebarLeft.keybinds
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Hyprland

Scope {
    id: root

    function toggle() {
        GlobalStates.cheatsheetOpen = !GlobalStates.cheatsheetOpen;
    }

    Loader {
        id: cheatsheetLoader
        active: GlobalStates.cheatsheetOpen
        sourceComponent: PanelWindow {
            id: cheatsheetWindow
            WlrLayershell.namespace: "quickshell:cheatsheet"
            WlrLayershell.layer: WlrLayer.Overlay
            WlrLayershell.keyboardFocus: GlobalStates.cheatsheetOpen ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None
            visible: true
            color: "transparent"

            anchors {
                bottom: true
                left: true
                right: true
            }
            margins {
                bottom: 0
            }
            implicitHeight: Math.min(600, Quickshell.screens[0]?.height * 0.6 ?? 500)

            HyprlandFocusGrab {
                id: grab
                windows: [cheatsheetWindow]
                active: GlobalStates.cheatsheetOpen
                onCleared: () => {
                    GlobalStates.cheatsheetOpen = false;
                }
            }

            Rectangle {
                id: cheatsheetBg
                anchors.fill: parent
                color: Appearance.colors.colLayer0
                border.width: 1
                border.color: ColorUtils.transparentize(Appearance.colors.colLayer0Border, 0.8)
                radius: Appearance.rounding.screenRounding

                ColumnLayout {
                    anchors.fill: parent
                    anchors.margins: 16
                    spacing: 10

                    // Header
                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 8

                        StyledText {
                            text: Translation.tr("Key Binds")
                            color: Appearance.colors.colOnLayer1
                            font.pixelSize: Appearance.font.pixelSize.large
                            font.weight: Font.DemiBold
                            Layout.fillWidth: true
                        }

                        RippleButton {
                            implicitWidth: 32
                            implicitHeight: 32
                            buttonRadius: Appearance.rounding.full
                            colBackground: Appearance.colors.colLayer2
                            colBackgroundHover: Appearance.colors.colLayer2Hover
                            onClicked: GlobalStates.cheatsheetOpen = false
                            contentItem: MaterialSymbol {
                                anchors.centerIn: parent
                                text: "close"
                                iconSize: Appearance.font.pixelSize.normal
                                color: Appearance.colors.colOnLayer1
                            }
                            StyledToolTip { text: Translation.tr("Close (Esc)") }
                        }
                    }

                    // KeyBinds content
                    KeyBinds {
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                    }
                }

                Keys.onPressed: (event) => {
                    if (event.key === Qt.Key_Escape) {
                        GlobalStates.cheatsheetOpen = false;
                        event.accepted = true;
                    }
                }
            }
        }
    }

    IpcHandler {
        target: "cheatsheet"

        function toggle(): void {
            root.toggle();
        }

        function open(): void {
            GlobalStates.cheatsheetOpen = true;
        }

        function close(): void {
            GlobalStates.cheatsheetOpen = false;
        }
    }

    CompositorGlobalShortcut {
        name: "cheatsheetToggle"
        description: "Toggles the cheatsheet on press"

        onPressed: {
            root.toggle();
        }
    }
}
