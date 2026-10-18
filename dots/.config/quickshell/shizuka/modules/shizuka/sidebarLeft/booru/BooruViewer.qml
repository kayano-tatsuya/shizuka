import qs
import qs.services
import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell

/**
 * AE-style booru browser for the left sidebar.
 *
 * Loads images immediately (no tag required), supports provider switching,
 * tag search with autocomplete, masonry display, pagination, NSFW gating,
 * per-image bookmarks and an AE-style detail panel that opens in a side popup
 * when a tile is clicked. All networking lives in the `Booru` service; this
 * file is presentation + paging state only.
 */
Item {
    id: root

    property real padding: 4

    property string tagText: ""
    property int page: 1
    property bool bookmarksMode: false
    property var images: []
    property string message: ""
    property bool loading: false
    property int pendingPage: 1
    property bool settingsOpen: false

    // The image whose detail card is open in the side popup, or null.
    property var detailImage: null

    property var suggestionList: []
    property string suggestionQuery: ""

    readonly property var providers: Booru.providerList
    readonly property string provider: Booru.currentProvider
    readonly property bool allowNsfw: Persistent.states.booru.allowNsfw
    readonly property int columns: Math.max(1, Math.min(4, Config.options.sidebar.booru.columns))
    readonly property int limit: Config.options.sidebar.booru.limit
    readonly property var bookmarks: Persistent.states.booru.bookmarks ?? []
    readonly property var displayImages: root.bookmarksMode ? root.bookmarks : root.images

    function tagList() {
        const t = root.tagText.trim();
        return t.length ? t.split(/\s+/) : [];
    }

    function load(reset, nsfwOverride) {
        if (reset) root.page = 1;
        root.pendingPage = root.page;
        root.loading = true;
        root.message = "";
        root.images = [];
        Booru.clearResponses();
        // Allow callers (e.g. the NSFW toggle) to pass the intended value
        // explicitly, so a stale property binding can't make the request use
        // the previous NSFW setting.
        const nsfw = (nsfwOverride === undefined) ? root.allowNsfw : nsfwOverride;
        Booru.makeRequest(root.tagList(), nsfw, root.limit, root.page);
    }

    function setProvider(p) {
        if (p === root.provider) return;
        Booru.setProvider(p);
        root.suggestionList = [];
        root.load(true);
    }

    // ---- bookmarks -------------------------------------------------------
    function sameImage(a, b) {
        return a && b && String(a.id) === String(b.id);
    }
    function isBookmarked(image) {
        return root.bookmarks.some(b => root.sameImage(b, image));
    }
    function toggleBookmark(image) {
        if (!image) return;
        const existing = root.bookmarks.findIndex(b => root.sameImage(b, image));
        let next = root.bookmarks.slice();
        if (existing >= 0) {
            next.splice(existing, 1);
        } else {
            next.unshift(Object.assign({}, image, { provider: root.provider }));
        }
        Persistent.states.booru.bookmarks = next;
    }

    // ---- detail panel (AE-style side popup) ------------------------------
    function openDetail(image) {
        if (!image) return;
        root.detailImage = image;
    }
    function closeDetail() {
        GlobalFocusGrab.suspended = false;
        root.detailImage = null;
    }
    // Toggle the sidebar waifu from the grid/detail. `Waifu` owns the state.
    function toggleWaifu(image) {
        if (!image) return;
        if (Waifu.isCurrent(image)) Waifu.clearWaifu();
        else Waifu.setWaifu(image);
    }
    // A tag chip in the detail panel was clicked: add it to the search and run.
    function activateTag(tag) {
        if (!tag || tag.length === 0) return;
        const parts = root.tagText.trim().split(/\s+/).filter(part => part.length > 0);
        if (parts.indexOf(tag) === -1) parts.push(tag);
        root.tagText = parts.join(" ") + " ";
        tagField.text = root.tagText;
        root.closeDetail();
        root.load(true);
    }

    // ---- tag autocomplete ------------------------------------------------
    Timer {
        id: suggestionTimer
        interval: 220
        repeat: false
        onTriggered: {
            const parts = root.tagText.trim().split(/\s+/);
            const last = parts[parts.length - 1] ?? "";
            if (last.length < 2) {
                root.suggestionList = [];
                return;
            }
            root.suggestionQuery = last;
            Booru.triggerTagSearch(last);
        }
    }

    Connections {
        target: Booru
        function onTagSuggestion(query, suggestions) {
            if (query !== root.suggestionQuery) return;
            root.suggestionList = suggestions ?? [];
        }
        function onResponseFinished() {
            const resp = Booru.responses.length ? Booru.responses[Booru.responses.length - 1] : null;
            root.loading = false;
            if (!resp) return;
            root.images = resp.images ?? [];
            root.message = resp.message ?? "";
        }
    }

    // Both the persisted provider and the keyring load asynchronously. Firing
    // a request before either is ready would use the wrong provider and send
    // no credentials (→ 401), which reads as "my API keys don't work".
    // NOTE: read the live values here rather than a cached binding — a binding
    // is not guaranteed to have re-evaluated by the time a change handler runs.
    function maybeInitialLoad() {
        if (Persistent.ready && KeyringStorage.loaded && root.images.length === 0 && !root.loading)
            root.load(true);
    }

    Component.onCompleted: root.maybeInitialLoad()

    Connections {
        target: Persistent
        function onReadyChanged() { root.maybeInitialLoad(); }
    }

    Connections {
        target: KeyringStorage
        function onLoadedChanged() { root.maybeInitialLoad(); }
    }

    ColumnLayout {
        anchors {
            fill: parent
            margins: root.padding
        }
        spacing: 6

        // ---- provider chips ---------------------------------------------
        StyledFlickable {
            Layout.fillWidth: true
            implicitHeight: providerRow.implicitHeight
            contentWidth: providerRow.implicitWidth
            contentHeight: providerRow.implicitHeight
            flickableDirection: Flickable.HorizontalFlick
            clip: true
            boundsBehavior: Flickable.StopAtBounds

            Row {
                id: providerRow
                spacing: 4
                Repeater {
                    model: root.providers
                    delegate: RippleButton {
                        id: chipDelegate
                        required property string modelData
                        readonly property bool active: modelData === root.provider
                        implicitHeight: 30
                        implicitWidth: chipLabel.implicitWidth + 18
                        buttonRadius: Appearance.rounding.full
                        toggled: active
                        colBackground: Appearance.colors.colLayer2
                        colBackgroundHover: Appearance.colors.colLayer2Hover
                        colBackgroundToggled: Appearance.colors.colPrimaryContainer
                        colBackgroundToggledHover: Appearance.colors.colPrimaryContainerHover
                        onClicked: root.setProvider(modelData)
                        contentItem: StyledText {
                            id: chipLabel
                            anchors.centerIn: parent
                            text: Booru.providers[chipDelegate.modelData]?.name ?? chipDelegate.modelData
                            color: chipDelegate.active ? Appearance.colors.colOnPrimaryContainer : Appearance.colors.colOnLayer1
                            font.pixelSize: Appearance.font.pixelSize.small
                        }
                    }
                }
            }
        }

        // ---- search row --------------------------------------------------
        RowLayout {
            Layout.fillWidth: true
            spacing: 6

            Rectangle {
                id: tagFieldArea
                Layout.fillWidth: true
                Layout.preferredHeight: 40
                radius: Appearance.rounding.small
                color: tagField.activeFocus ? Appearance.colors.colLayer2 : Appearance.colors.colLayer1
                border.width: (tagHover.hovered || tagField.activeFocus) ? (tagField.activeFocus ? 2 : 1) : 0
                border.color: tagField.activeFocus ? Appearance.colors.colPrimary : Appearance.colors.colOutlineVariant

                HoverHandler { id: tagHover }

                TextField {
                    id: tagField
                    anchors.fill: parent
                    anchors.leftMargin: 12
                    anchors.rightMargin: 12
                    verticalAlignment: TextInput.AlignVCenter
                    placeholderText: Translation.tr("Search tags (optional)")
                    placeholderTextColor: Appearance.colors.colSubtext
                    color: Appearance.colors.colOnLayer1
                    selectedTextColor: Appearance.colors.colOnSecondaryContainer
                    selectionColor: Appearance.colors.colSecondaryContainer
                    selectByMouse: true
                    background: null
                    padding: 0
                    font {
                        family: Appearance.font.family.main
                        pixelSize: Appearance.font.pixelSize.small
                        hintingPreference: Font.PreferFullHinting
                        variableAxes: Appearance.font.variableAxes.main
                    }
                    onTextChanged: {
                        root.tagText = text;
                        suggestionTimer.restart();
                    }
                    onAccepted: {
                        root.suggestionList = [];
                        root.load(true);
                    }
                }
            }

            RippleButton {
                implicitWidth: 40
                implicitHeight: 40
                buttonRadius: Appearance.rounding.small
                colBackground: Appearance.colors.colLayer2
                colBackgroundHover: Appearance.colors.colLayer2Hover
                onClicked: {
                    root.suggestionList = [];
                    root.load(true);
                }
                contentItem: MaterialSymbol {
                    horizontalAlignment: Text.AlignHCenter
                    verticalAlignment: Text.AlignVCenter
                    text: "search"
                    iconSize: Appearance.font.pixelSize.large
                    color: Appearance.colors.colOnLayer1
                }
                StyledToolTip { text: Translation.tr("Search") }
            }

            // NSFW toggle
            RippleButton {
                implicitWidth: 40
                implicitHeight: 40
                buttonRadius: Appearance.rounding.small
                toggled: root.allowNsfw
                colBackground: Appearance.colors.colLayer2
                colBackgroundHover: Appearance.colors.colLayer2Hover
                colBackgroundToggled: Appearance.colors.colErrorContainer
                colBackgroundToggledHover: Appearance.colors.colErrorContainerHover
                onClicked: {
                    const next = !root.allowNsfw;
                    Persistent.states.booru.allowNsfw = next;
                    root.load(true, next);
                }
                contentItem: MaterialSymbol {
                    horizontalAlignment: Text.AlignHCenter
                    verticalAlignment: Text.AlignVCenter
                    text: root.allowNsfw ? "visibility" : "visibility_off"
                    iconSize: Appearance.font.pixelSize.large
                    color: root.allowNsfw ? Appearance.colors.colOnErrorContainer : Appearance.colors.colOnLayer1
                }
                StyledToolTip {
                    text: root.allowNsfw
                        ? Translation.tr("NSFW allowed — click to hide")
                        : Translation.tr("NSFW hidden — click to allow (needs provider account for some sites)")
                }
            }

            // Bookmarks
            RippleButton {
                implicitWidth: 40
                implicitHeight: 40
                buttonRadius: Appearance.rounding.small
                toggled: root.bookmarksMode
                colBackground: Appearance.colors.colLayer2
                colBackgroundHover: Appearance.colors.colLayer2Hover
                colBackgroundToggled: Appearance.colors.colPrimaryContainer
                colBackgroundToggledHover: Appearance.colors.colPrimaryContainerHover
                onClicked: {
                    root.bookmarksMode = !root.bookmarksMode;
                    root.suggestionList = [];
                }
                contentItem: MaterialSymbol {
                    horizontalAlignment: Text.AlignHCenter
                    verticalAlignment: Text.AlignVCenter
                    text: root.bookmarksMode ? "bookmark_added" : "bookmark"
                    iconSize: Appearance.font.pixelSize.large
                    color: root.bookmarksMode ? Appearance.colors.colOnPrimaryContainer : Appearance.colors.colOnLayer1
                }
                StyledToolTip { text: Translation.tr("Bookmarks") }
            }

            // Settings
            RippleButton {
                implicitWidth: 40
                implicitHeight: 40
                buttonRadius: Appearance.rounding.small
                toggled: root.settingsOpen
                colBackground: Appearance.colors.colLayer2
                colBackgroundHover: Appearance.colors.colLayer2Hover
                colBackgroundToggled: Appearance.colors.colSecondaryContainer
                colBackgroundToggledHover: Appearance.colors.colSecondaryContainerHover
                onClicked: {
                    root.settingsOpen = !root.settingsOpen;
                    root.suggestionList = [];
                }
                contentItem: MaterialSymbol {
                    horizontalAlignment: Text.AlignHCenter
                    verticalAlignment: Text.AlignVCenter
                    text: "tune"
                    iconSize: Appearance.font.pixelSize.large
                    color: root.settingsOpen ? Appearance.colors.colOnSecondaryContainer : Appearance.colors.colOnLayer1
                }
                StyledToolTip { text: Translation.tr("Viewer settings") }
            }
        }

        // ---- body --------------------------------------------------------
        Rectangle {
            Layout.fillWidth: true
            Layout.fillHeight: true
            radius: Appearance.rounding.small
            color: Appearance.colors.colLayer0

            Item {
                anchors.fill: parent

                // Tag autocomplete dropdown (inline, overlays the top of the body)
                Rectangle {
                    id: suggestionPopup
                    z: 100
                    visible: root.suggestionList.length > 0 && tagField.activeFocus && !root.bookmarksMode
                    x: 6
                    y: 2
                    width: Math.max(140, tagFieldArea.width - 12)
                    height: Math.min(220, suggColumn.implicitHeight + 12)
                    radius: Appearance.rounding.small
                    color: Appearance.colors.colLayer2
                    border.width: 1
                    border.color: Appearance.colors.colOutlineVariant
                    clip: true

                    Column {
                        id: suggColumn
                        anchors.fill: parent
                        anchors.margins: 6
                        spacing: 2

                        Repeater {
                            model: root.suggestionList.slice(0, 8)
                            delegate: RippleButton {
                                required property var modelData
                                width: suggColumn.width
                                implicitHeight: 30
                                buttonRadius: Appearance.rounding.small
                                colBackground: "transparent"
                                colBackgroundHover: Appearance.colors.colLayer2Hover
                                rippleEnabled: false
                                contentItem: StyledText {
                                    anchors.fill: parent
                                    anchors.leftMargin: 8
                                    anchors.rightMargin: 8
                                    verticalAlignment: Text.AlignVCenter
                                    elide: Text.ElideRight
                                    text: modelData.name + (modelData.count !== undefined ? "  (" + modelData.count + ")" : "")
                                    color: Appearance.colors.colOnLayer1
                                    font.pixelSize: Appearance.font.pixelSize.small
                                }
                                onClicked: {
                                    const parts = root.tagText.trim().split(/\s+/);
                                    parts[parts.length - 1] = modelData.name;
                                    root.tagText = parts.join(" ") + " ";
                                    tagField.text = root.tagText;
                                    root.suggestionList = [];
                                    tagField.forceActiveFocus();
                                }
                            }
                        }
                    }
                }

                // Settings overlay
                ColumnLayout {
                    anchors.fill: parent
                    anchors.margins: 8
                    visible: root.settingsOpen
                    spacing: 6

                    StyledText {
                        text: Translation.tr("Viewer settings")
                        font.pixelSize: Appearance.font.pixelSize.large
                        color: Appearance.colors.colOnLayer1
                    }
                    ConfigSpinBox {
                        icon: "view_column"
                        text: Translation.tr("Columns")
                        value: Config.options.sidebar.booru.columns
                        from: 1
                        to: 4
                        stepSize: 1
                        onValueChanged: Config.options.sidebar.booru.columns = value
                    }
                    ConfigSpinBox {
                        icon: "format_list_numbered"
                        text: Translation.tr("Results per page")
                        value: Config.options.sidebar.booru.limit
                        from: 6
                        to: 60
                        stepSize: 2
                        onValueChanged: Config.options.sidebar.booru.limit = value
                    }
                    StyledText {
                        Layout.fillWidth: true
                        visible: root.bookmarksMode
                        text: Translation.tr("%1 bookmarks").arg(root.bookmarks.length)
                        color: Appearance.colors.colSubtext
                        font.pixelSize: Appearance.font.pixelSize.smaller
                    }
                    Item { Layout.fillHeight: true }
                }

                // Grid / message
                StyledFlickable {
                    id: scroll
                    anchors.fill: parent
                    visible: !root.settingsOpen
                    clip: true
                    contentWidth: width
                    contentHeight: root.displayImages.length > 0 ? grid.height + 12 : emptyText.height + 24
                    boundsBehavior: Flickable.StopAtBounds

                    AppMasonry {
                        id: grid
                        width: scroll.width - 12
                        x: 6
                        y: 6
                        model: root.displayImages
                        columns: root.columns
                        spacing: 6
                        aspectRatio: item => (item.width > 0 && item.height > 0) ? item.height / item.width : 1
                        delegate: BooruTile {
                            imageData: modelData
                            allowNsfw: root.allowNsfw
                            bookmarked: root.isBookmarked(modelData)
                            isWaifu: Waifu.isCurrent(modelData)
                            onActivate: root.openDetail(modelData)
                            onToggleBookmark: root.toggleBookmark(modelData)
                            onSetWaifu: root.toggleWaifu(modelData)
                        }
                    }

                    StyledText {
                        id: emptyText
                        visible: root.displayImages.length === 0
                        width: parent.width - 24
                        x: 12
                        y: 24
                        horizontalAlignment: Text.AlignHCenter
                        wrapMode: Text.Wrap
                        color: Appearance.colors.colSubtext
                        text: root.loading
                            ? Translation.tr("Loading…")
                            : (root.bookmarksMode
                                ? Translation.tr("No bookmarks yet.\nRight-click an image to bookmark it.")
                                : (root.message.length > 0 ? root.message : Translation.tr("No results.")))
                    }
                }

                BusyIndicator {
                    anchors.centerIn: parent
                    visible: root.loading && !root.settingsOpen
                    running: visible
                }
            }
        }

        // ---- footer / paging --------------------------------------------
        RowLayout {
            Layout.fillWidth: true
            visible: !root.bookmarksMode
            spacing: 6

            RippleButton {
                implicitWidth: 36
                implicitHeight: 32
                buttonRadius: Appearance.rounding.small
                colBackground: Appearance.colors.colLayer2
                colBackgroundHover: Appearance.colors.colLayer2Hover
                enabled: root.page > 1 && !root.loading
                onClicked: {
                    root.page = Math.max(1, root.page - 1);
                    root.load(false);
                }
                contentItem: MaterialSymbol {
                    horizontalAlignment: Text.AlignHCenter
                    verticalAlignment: Text.AlignVCenter
                    text: "chevron_left"
                    iconSize: Appearance.font.pixelSize.large
                    color: Appearance.colors.colOnLayer1
                }
            }

            StyledText {
                Layout.fillWidth: true
                horizontalAlignment: Text.AlignHCenter
                text: Translation.tr("Page %1").arg(root.page)
                color: Appearance.colors.colSubtext
            }

            RippleButton {
                implicitWidth: 36
                implicitHeight: 32
                buttonRadius: Appearance.rounding.small
                colBackground: Appearance.colors.colLayer2
                colBackgroundHover: Appearance.colors.colLayer2Hover
                enabled: !root.loading
                onClicked: {
                    root.page = root.page + 1;
                    root.load(false);
                }
                contentItem: MaterialSymbol {
                    horizontalAlignment: Text.AlignHCenter
                    verticalAlignment: Text.AlignVCenter
                    text: "chevron_right"
                    iconSize: Appearance.font.pixelSize.large
                    color: Appearance.colors.colOnLayer1
                }
            }
        }
    }

    // ---- detail side panel (AE-style popup window) ----------------------
    // Closes itself when the sidebar hides or the booru tab is left, so an
    // orphan card can never outlive the surface it is docked to.
    readonly property bool booruActive: SwipeView.isCurrentItem
    onBooruActiveChanged: if (!root.booruActive) root.closeDetail()

    Connections {
        target: GlobalStates
        function onSidebarLeftOpenChanged() {
            if (!GlobalStates.sidebarLeftOpen) root.closeDetail();
        }
    }


    // Detail panel. Rendered as an in-sidebar overlay (not a separate
    // window) so it stays inside the sidebar surface: that keeps the focus
    // grab from dismissing the sidebar when it opens, and lets its buttons
    // receive clicks. It covers the viewer while open; closing returns to
    // the grid.
    Rectangle {
        id: detailOverlay
        anchors.fill: parent
        visible: root.detailImage !== null
        z: 10
        color: Appearance.colors.colLayer0
        radius: Appearance.rounding.small
        clip: true

        StyledRectangularShadow {
            target: detailCard
        }
        BooruDetail {
            id: detailCard
            anchors.fill: parent
            anchors.margins: Appearance.sizes.elevationMargin
            image: root.detailImage
            allowNsfw: root.allowNsfw
            bookmarked: root.isBookmarked(root.detailImage)
            isWaifu: Waifu.isCurrent(root.detailImage)
            onCloseRequested: root.closeDetail()
            onToggleBookmarkRequested: root.toggleBookmark(root.detailImage)
            onSetWaifuRequested: root.toggleWaifu(root.detailImage)
            onTagActivated: (tag) => root.activateTag(tag)
        }
    }

}
