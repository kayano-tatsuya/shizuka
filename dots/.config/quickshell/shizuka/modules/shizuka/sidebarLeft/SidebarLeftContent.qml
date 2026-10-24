import qs.services
import qs.modules.common
import qs.modules.common.widgets
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Qt5Compat.GraphicalEffects
import Qt.labs.synchronizer
import "booru"
import "keybinds"

Item {
    id: root
    required property var scopeRoot
    property int sidebarPadding: 10
    anchors.fill: parent
    property bool aiChatEnabled: Config.options.policies.ai !== 0
    property bool translatorEnabled: Config.options.sidebar.translator.enable
    property bool booruEnabled: Config.options.policies.weeb !== 0
    property bool weebCloset: Config.options.policies.weeb === 2
    property bool mediaEnabled: Config.options.sidebar.media.enable
    property var tabButtonList: [
        ...(root.aiChatEnabled ? [{"icon": "neurology", "name": Translation.tr("Intelligence")}] : []),
        ...(root.translatorEnabled ? [{"icon": "translate", "name": Translation.tr("Translator")}] : []),
        ...(root.mediaEnabled ? [{"icon": "music_note", "name": Translation.tr("Media")}] : []),
        ...((root.booruEnabled && !root.weebCloset) ? [{"icon": "image", "name": Translation.tr("Booru")}] : [])
        , {"icon": "keyboard", "name": Translation.tr("Key Binds")}
    ]
    property int tabCount: swipeView.count

    function focusActiveItem() {
        swipeView.currentItem.forceActiveFocus()
    }

    Keys.onPressed: (event) => {
        if (event.modifiers === Qt.ControlModifier) {
            if (event.key === Qt.Key_PageDown) {
                swipeView.incrementCurrentIndex()
                event.accepted = true
            }
            else if (event.key === Qt.Key_PageUp) {
                swipeView.decrementCurrentIndex()
                event.accepted = true
            }
        }
    }

    ColumnLayout {
        anchors {
            fill: parent
            margins: sidebarPadding
        }
        spacing: verticalTabBar.expanded ? -2 : 0

        VerticalTabBar {
            id: verticalTabBar
            visible: tabButtonList.length > 0
            Layout.fillWidth: true
            tabButtonList: root.tabButtonList
            currentIndex: swipeView.currentIndex
            onCurrentIndexChanged: swipeView.currentIndex = currentIndex
        }

        Rectangle {
            id: contentRect
            Layout.fillWidth: true
            Layout.fillHeight: true
            implicitWidth: swipeView.implicitWidth
            implicitHeight: swipeView.implicitHeight

            topLeftRadius: 0
            bottomLeftRadius: Appearance.rounding.normal
            topRightRadius: 0
            bottomRightRadius: Appearance.rounding.normal
            color: Appearance.colors.colLayer1

            SwipeView { // Content pages
                id: swipeView
                anchors.fill: parent
                spacing: 10
                currentIndex: tabBar.currentIndex
                interactive: false

                clip: true
                layer.enabled: false

                contentChildren: [
                    ...(root.aiChatEnabled ? [aiChat.createObject()] : []),
                    ...(root.translatorEnabled ? [translator.createObject()] : []),
                    ...(root.mediaEnabled ? [media.createObject()] : []),
                    ...((root.tabButtonList.length === 0 || (!root.aiChatEnabled && !root.translatorEnabled && root.weebCloset)) ? [placeholder.createObject()] : []),
                    ...(root.booruEnabled ? [booru.createObject()] : []),
                    keybinds.createObject(),
                ]
            }
        }
    }

    // Detail panel overlay (booru). Sibling of the ColumnLayout so it is
    // not managed by the layout and its buttons receive input reliably.
    Rectangle {
        id: booruDetailOverlay
        anchors.fill: parent
        visible: root.booruEnabled && (swipeView.currentItem?.detailImage ?? null) !== null
        z: 10
        color: Appearance.colors.colLayer0
        radius: Appearance.rounding.small
        clip: true

        BooruDetail {
            id: booruDetailCard
            anchors.fill: parent
            anchors.margins: Appearance.sizes.elevationMargin
            image: swipeView.currentItem?.detailImage ?? null
            allowNsfw: swipeView.currentItem?.allowNsfw ?? false
            bookmarked: {
                const v = swipeView.currentItem;
                return (v && typeof v.isBookmarked === "function") ? v.isBookmarked(v.detailImage) : false;
            }
            isWaifu: {
                const v = swipeView.currentItem;
                return v ? Waifu.isCurrent(v.detailImage) : false;
            }
            onCloseRequested: {
                const v = swipeView.currentItem;
                if (v && typeof v.closeDetail === "function") v.closeDetail();
            }
            onToggleBookmarkRequested: {
                const v = swipeView.currentItem;
                if (v && typeof v.toggleBookmark === "function") v.toggleBookmark(v.detailImage);
            }
            onSetWaifuRequested: {
                const v = swipeView.currentItem;
                if (v && typeof v.toggleWaifu === "function") v.toggleWaifu(v.detailImage);
            }
            onTagActivated: (tag) => {
                const v = swipeView.currentItem;
                if (v && typeof v.activateTag === "function") v.activateTag(tag);
            }
        }
    }

    Component {
        id: aiChat
        AiChat {}
    }
    Component {
        id: translator
        Translator {}
    }
    Component {
        id: media
        SidebarPlayerControl {}
    }
    Component {
        id: booru
        BooruViewer {}
    }
    Component {
        id: keybinds
        KeyBinds {}
    }
    Component {
        id: placeholder
        Item {
            StyledText {
                anchors.centerIn: parent
                text: root.weebCloset ? Translation.tr("Nothing") : Translation.tr("Enjoy your empty sidebar...")
                color: Appearance.colors.colSubtext
            }
        }
    }












}
