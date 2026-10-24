import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell

/**
 * KeyBinds viewer for the left sidebar. Reads the Hyprland Lua keybinds
 * (via HyprlandKeybinds), groups them by category, and renders each binding
 * as a description plus key chips joined by "+".
 */
Item {
    id: root
    property real padding: 4

    // ---- search ---------------------------------------------------------
    property string searchText: ""
    readonly property var allCategories: {
        const kb = HyprlandKeybinds.keybinds;
        const cats = (kb && kb.children) ? kb.children : [];
        return cats.filter(c => (c.keybinds || []).length > 0);
    }
    readonly property var filteredCategories: {
        const q = root.searchText.trim().toLowerCase();
        if (q.length === 0) return root.allCategories;
        const out = [];
        for (const c of root.allCategories) {
            const binds = (c.keybinds || []).filter(b => {
                const desc = (b.comment || "").toLowerCase();
                const keys = ((b.mods || []).concat([b.key || ""])).join(" ").toLowerCase();
                return desc.includes(q) || keys.includes(q) || (c.name || "").toLowerCase().includes(q);
            });
            if (binds.length > 0)
                out.push({ name: c.name, keybinds: binds });
        }
        return out;
    }
    readonly property int totalBinds: {
        let n = 0;
        for (const c of root.filteredCategories) n += (c.keybinds || []).length;
        return n;
    }

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: root.padding
        spacing: 8

        // ---- header + search -------------------------------------------
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
                onClicked: HyprlandKeybinds.getDefaultKeybinds.running = true
                contentItem: MaterialSymbol {
                    anchors.centerIn: parent
                    text: "refresh"
                    iconSize: Appearance.font.pixelSize.normal
                    color: Appearance.colors.colOnLayer1
                }
                StyledToolTip { text: Translation.tr("Reload keybinds") }
            }
        }

        // search field
        Rectangle {
            Layout.fillWidth: true
            implicitHeight: 34
            radius: Appearance.rounding.small
            color: Appearance.colors.colLayer2
            border.width: 1
            border.color: ColorUtils.transparentize(Appearance.colors.colLayer0Border, 0.8)

            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: 10
                anchors.rightMargin: 10
                spacing: 6

                MaterialSymbol {
                    text: "search"
                    iconSize: Appearance.font.pixelSize.normal
                    color: Appearance.colors.colSubtext
                }
                TextField {
                    id: searchField
                    Layout.fillWidth: true
                    placeholderText: Translation.tr("Search keybinds...")
                    color: Appearance.colors.colOnLayer1
                    placeholderTextColor: Appearance.colors.colSubtext
                    font.pixelSize: Appearance.font.pixelSize.small
                    background: null
                    onTextChanged: root.searchText = text
                }
            }
        }

        // ---- list ------------------------------------------------------
        StyledFlickable {
            Layout.fillWidth: true
            Layout.fillHeight: true
            clip: true
            contentWidth: width
            contentHeight: keyCol.implicitHeight
            boundsBehavior: Flickable.StopAtBounds

            Column {
                id: keyCol
                width: parent.width
                spacing: 12

                Repeater {
                    model: root.filteredCategories
                    delegate: Column {
                        required property var modelData
                        width: parent.width
                        spacing: 4

                        StyledText {
                            text: modelData.name ?? Translation.tr("Unnamed")
                            color: Appearance.colors.colOnLayer1
                            font.pixelSize: Appearance.font.pixelSize.normal
                            font.weight: Font.DemiBold
                            width: parent.width
                            elide: Text.ElideRight
                        }

                        Repeater {
                            model: modelData.keybinds || []
                            delegate: Rectangle {
                                required property var modelData
                                width: parent.width
                                height: 26
                                color: "transparent"

                                RowLayout {
                                    anchors.fill: parent
                                    spacing: 8

                                    StyledText {
                                        text: modelData.comment && modelData.comment.length > 0
                                            ? modelData.comment
                                            : (modelData.dispatcher || "")
                                        color: Appearance.colors.colOnLayer1
                                        font.pixelSize: Appearance.font.pixelSize.small
                                        elide: Text.ElideRight
                                        Layout.fillWidth: true
                                        maximumLineCount: 1
                                    }

                                    Row {
                                        spacing: 3
                                        Layout.alignment: Qt.AlignVCenter

                                        Repeater {
                                            model: (modelData.mods || []).concat(modelData.key ? [modelData.key] : [])
                                            delegate: Rectangle {
                                                required property string modelData
                                                required property int index
                                                readonly property bool isLast: index === ((modelData.mods || []).concat(modelData.key ? [modelData.key] : [])).length - 1
                                                // need total count; recompute below
                                                implicitWidth: chipText.implicitWidth + 10
                                                implicitHeight: 20
                                                radius: Appearance.rounding.small
                                                color: Appearance.colors.colLayer2
                                                border.width: 1
                                                border.color: ColorUtils.transparentize(Appearance.colors.colLayer0Border, 0.8)

                                                StyledText {
                                                    id: chipText
                                                    anchors.centerIn: parent
                                                    text: modelData
                                                    font.pixelSize: Appearance.font.pixelSize.smaller
                                                    font.weight: Font.Medium
                                                    color: Appearance.colors.colOnLayer1
                                                }
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }
                }

                // Empty state
                StyledText {
                    visible: root.totalBinds === 0
                    width: parent.width
                    horizontalAlignment: Text.AlignHCenter
                    text: Translation.tr("No keybinds found")
                    color: Appearance.colors.colSubtext
                    font.pixelSize: Appearance.font.pixelSize.small
                }
            }
        }
    }
}
