import qs.modules.common
import qs.modules.common.widgets
import qs.services
import QtQuick
import QtQuick.Layouts
import QtQuick.Controls

/**
 * A single secret (API key / token / username) field backed by KeyringStorage.
 *
 * The value is read from (and written to) the keyring JSON at `keyPath`, e.g.
 *   ["apiKeys", "wallhaven"]           -> keyringData.apiKeys.wallhaven
 *   ["apiKeys", "danbooru", "key"]     -> keyringData.apiKeys.danbooru.key
 * This mirrors the flat/nested convention already used across the shell
 * (LauncherSearch /wallhaven, Ai model keys, OnlineWallpapers).
 *
 * Secrets are masked by default with a reveal toggle; saving happens on the
 * check button or Enter.
 */
RowLayout {
    id: root

    property var keyPath: []
    property string text: ""
    property string description: ""
    property string buttonIcon: "key"
    property string placeholderText: ""
    property string getLink: ""        // Optional URL where the key can be obtained
    property string getLinkHint: ""
    property bool revealed: false
    property bool justSaved: false

    readonly property string storedValue: {
        let v = KeyringStorage.keyringData;
        for (let i = 0; i < root.keyPath.length; ++i) {
            if (v === undefined || v === null) return "";
            v = v[root.keyPath[i]];
        }
        return (v === undefined || v === null) ? "" : String(v);
    }

    function reload() {
        if (!field.activeFocus) field.text = root.storedValue;
    }

    function save() {
        KeyringStorage.setNestedField(root.keyPath, field.text.trim());
        root.justSaved = true;
        savedTimer.restart();
    }

    function clear() {
        field.text = "";
        KeyringStorage.setNestedField(root.keyPath, "");
    }

    spacing: 10
    Layout.leftMargin: 8
    Layout.rightMargin: 8

    OptionalMaterialSymbol {
        icon: root.buttonIcon
        iconSize: Appearance.font.pixelSize.larger
    }

    ColumnLayout {
        Layout.fillWidth: true
        spacing: 0
        StyledText {
            Layout.fillWidth: true
            text: root.text
            color: Appearance.colors.colOnSecondaryContainer
        }
        StyledText {
            Layout.fillWidth: true
            visible: root.description.length > 0
            text: root.description
            font.pixelSize: Appearance.font.pixelSize.smaller
            color: Appearance.colors.colSubtext
            wrapMode: Text.Wrap
            Layout.maximumWidth: 240
        }
    }

    Rectangle {
        id: fieldBg
        Layout.preferredWidth: 230
        Layout.preferredHeight: 40
        Layout.alignment: Qt.AlignVCenter
        radius: Appearance.rounding.small
        clip: true
        color: field.activeFocus ? Appearance.colors.colLayer2 : Appearance.colors.colLayer1
        border.width: (hoverHandler.hovered || field.activeFocus) ? (field.activeFocus ? 2 : 1) : 0
        border.color: field.activeFocus ? Appearance.colors.colPrimary : Appearance.colors.colOutlineVariant

        Behavior on color {
            ColorAnimation { duration: Appearance.animation.elementMoveFast.duration }
        }

        HoverHandler { id: hoverHandler }

        TextField {
            id: field
            anchors.fill: parent
            anchors.leftMargin: 12
            anchors.rightMargin: 34
            verticalAlignment: TextInput.AlignVCenter
            selectByMouse: true
            echoMode: root.revealed ? TextInput.Normal : TextInput.Password
            placeholderText: root.placeholderText
            placeholderTextColor: Appearance.colors.colSubtext
            color: Appearance.colors.colOnLayer1
            selectedTextColor: Appearance.colors.colOnSecondaryContainer
            selectionColor: Appearance.colors.colSecondaryContainer
            background: null
            padding: 0
            font {
                family: Appearance.font.family.main
                pixelSize: Appearance.font.pixelSize.small
                hintingPreference: Font.PreferFullHinting
                variableAxes: Appearance.font.variableAxes.main
            }
            onAccepted: root.save()
        }

        MaterialSymbol {
            anchors.right: parent.right
            anchors.rightMargin: 8
            anchors.verticalCenter: parent.verticalCenter
            text: root.revealed ? "visibility_off" : "visibility"
            iconSize: Appearance.font.pixelSize.large
            color: Appearance.colors.colSubtext
            MouseArea {
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                onClicked: root.revealed = !root.revealed
            }
        }
    }

    // Open the provider's key page
    Rectangle {
        visible: root.getLink.length > 0
        Layout.preferredWidth: 40
        Layout.preferredHeight: 40
        Layout.alignment: Qt.AlignVCenter
        radius: Appearance.rounding.small
        color: linkMouse.pressed
            ? Appearance.colors.colLayer2Active
            : (linkMouse.containsMouse ? Appearance.colors.colLayer2Hover : Appearance.colors.colLayer1)

        MaterialSymbol {
            anchors.centerIn: parent
            text: "open_in_new"
            iconSize: Appearance.font.pixelSize.large
            color: Appearance.colors.colOnLayer1
        }
        MouseArea {
            id: linkMouse
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: Qt.openUrlExternally(root.getLink)
        }
    }

    // Save
    Rectangle {
        Layout.preferredWidth: 40
        Layout.preferredHeight: 40
        Layout.alignment: Qt.AlignVCenter
        radius: Appearance.rounding.small
        color: saveMouse.pressed
            ? Appearance.colors.colPrimaryContainerActive
            : (saveMouse.containsMouse ? Appearance.colors.colPrimaryContainerHover : Appearance.colors.colPrimaryContainer)

        MaterialSymbol {
            anchors.centerIn: parent
            text: root.justSaved ? "check" : "save"
            iconSize: Appearance.font.pixelSize.large
            color: Appearance.colors.colOnPrimaryContainer
        }
        MouseArea {
            id: saveMouse
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: root.save()
        }
    }

    Timer {
        id: savedTimer
        interval: 1500
        onTriggered: root.justSaved = false
    }

    Connections {
        target: KeyringStorage
        function onLoadedChanged() { root.reload(); }
        function onDataChanged() { root.reload(); }
        function onKeyringDataChanged() { root.reload(); }
    }

    Component.onCompleted: {
        if (!KeyringStorage.loaded) KeyringStorage.fetchKeyringData();
        root.reload();
    }
}
