import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Qt5Compat.GraphicalEffects
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland

// WallpaperSwitcherBody — AE-style wallpaper switcher: a horizontally-scrolling
// masonry strip (AppMasonryRow) with a provider switch (Local | Wallhaven),
// instead of the folder-browsing grid in WallpaperSelectorContent.
//
// Picked via Config.options.wallpaperSelector.style ("switcher"); the grid stays
// the default. Both bodies share the apply pipeline (Wallpapers.select →
// switchwall.sh) and the closeAfterSelection behaviour, so switching styles
// never changes what a click does.
//
// Local data comes from the shared WallpaperLibrary singleton (category map +
// video-thumb manifest + decoded-aspect cache, fetched once at boot). Wallhaven
// results come from the Wallhaven service; applying one downloads into
// <library>/wallhaven and then rides the ordinary local pipeline.
Item {
    id: root

    property bool useDarkMode: Appearance.m3colors.darkmode

    // "" is the library root; subdirectories are named by their relative path.
    property string selectedCategory: ""

    readonly property string provider: Config.options.wallpaperSelector.provider || "local"
    readonly property bool online: root.provider === "wallhaven"

    readonly property var categories: Object.keys(WallpaperLibrary.wallpapers || {})
    readonly property var localPaths: (WallpaperLibrary.wallpapers || {})[root.selectedCategory] || []
    readonly property var currentModel: root.online ? Wallhaven.results : root.localPaths

    readonly property bool libraryEmpty: !WallpaperLibrary.wallpapers
        || Object.keys(WallpaperLibrary.wallpapers || {}).length === 0
    readonly property bool onlineError: root.online && Wallhaven.error.length > 0
    // Springy progress vs. plain text in the empty strip.
    readonly property bool stripBusy: root.online ? Wallhaven.loading : root.libraryEmpty

    readonly property int rows: Math.max(1, Config.options.wallpaperSelector.masonryRows || 2)
    readonly property int tileSize: Math.max(64, Config.options.wallpaperSelector.tileSize || 120)
    readonly property string currentWallpaper: Config.options.background.wallpaperPath

    // Natural body height (toolbars + tile area + padding). The panel binds to
    // this in switcher mode so it hugs the content instead of leaving large
    // empty bands above/below a 2-row strip. Independent of the window height
    // (strip.implicitHeight == masonry.implicitHeight), so no binding loop.
    readonly property real idealHeight: Appearance.sizes.elevationMargin * 2
        + layout.anchors.topMargin + layout.anchors.bottomMargin
        + layout.implicitHeight

    function categoryLabel(key) {
        if (!key || key.length === 0)
            return Translation.tr("Library");
        const parts = key.split("/");
        return parts[parts.length - 1];
    }

    // Keep the combo and selectedCategory agreed whenever the library reloads.
    // A persistent `currentIndex` binding would be destroyed by the ComboBox's
    // own imperative writes, so we assign it explicitly instead.
    function ensureCategory() {
        if (root.categories.length === 0)
            return;
        let idx = root.categories.indexOf(root.selectedCategory);
        if (idx === -1) {
            idx = 0;
            root.selectedCategory = root.categories[0];
        }
        if (categoryCombo.currentIndex !== idx)
            categoryCombo.currentIndex = idx;
    }

    function isVideoItem(item) {
        return typeof item === "string" && WallpaperLibrary.isVideoFile(item);
    }

    // Local tiles are path strings (aspect from the decoded cache); Wallhaven
    // tiles are result objects (aspect from the API's ratio/resolution).
    function aspectFor(item) {
        if (typeof item === "string")
            return WallpaperLibrary.localAspectOf(item);
        if (item && item.ratio !== undefined && item.ratio !== "") {
            const r = parseFloat(item.ratio);
            if (isFinite(r) && r > 0)
                return r;
        }
        if (item && typeof item.resolution === "string" && item.resolution.indexOf("x") > 0) {
            const p = item.resolution.split("x");
            const w = parseFloat(p[0]);
            const h = parseFloat(p[1]);
            if (isFinite(w) && isFinite(h) && h > 0)
                return w / h;
        }
        return 16 / 9;
    }

    function tileSource(item) {
        if (typeof item === "string") {
            const thumb = WallpaperLibrary.thumbFor(item);
            if (thumb.length > 0)
                return Qt.resolvedUrl(thumb);
            return WallpaperLibrary.isVideoFile(item) ? "" : Qt.resolvedUrl(item);
        }
        return item ? (item.large || item.preview || "") : "";
    }

    function setTileSize(value) {
        Config.options.wallpaperSelector.tileSize = Math.max(64, Math.min(320, value));
    }

    function setRows(value) {
        Config.options.wallpaperSelector.masonryRows = Math.max(1, Math.min(4, value));
    }

    function setProvider(p) {
        Config.options.wallpaperSelector.provider = p;
        if (p === "wallhaven" && Wallhaven.results.length === 0 && !Wallhaven.loading)
            Wallhaven.search();
    }

    // Same target handling as WallpaperSelectorContent.selectWallpaperPath: the
    // lock target captures the path into config, the wallpaper target rides the
    // normal preview/apply pipeline (whose `changed` closes us when configured).
    function selectWallpaperPath(filePath) {
        if (!filePath || filePath.length === 0)
            return;
        if (GlobalStates.wallpaperSelectorTarget === "lockWall") {
            Wallpapers.select(filePath, root.useDarkMode, finalPath => {
                Config.options.background.lockWall = finalPath;
                GlobalStates.wallpaperSelectorTarget = "wallpaper";
                GlobalStates.wallpaperSelectorOpen = false;
            });
        } else if (GlobalStates.wallpaperSelectorTarget === "sddmWall") {
            Wallpapers.applySddmWallpaper(filePath);
            GlobalStates.wallpaperSelectorTarget = "wallpaper";
            GlobalStates.wallpaperSelectorOpen = false;
        } else if (GlobalStates.wallpaperSelectorTarget === "workspace") {
            const mon = Hyprland.focusedMonitor?.name ?? "";
            const ws = Hyprland.focusedMonitor?.activeWorkspace?.id ?? -1;
            Wallpapers.select(filePath, root.useDarkMode, finalPath => {
                if (mon.length > 0 && ws > 0)
                    WallpaperLibrary.setWorkspaceWallpaper(mon, ws, finalPath);
                GlobalStates.wallpaperSelectorTarget = "wallpaper";
                GlobalStates.wallpaperSelectorOpen = false;
            });
        } else {
            if (Config.options.background.enableWallpaperPreview)
                Wallpapers.stopPreview();
            Wallpapers.select(filePath, root.useDarkMode);
        }
    }

    function applyRandom() {
        const list = root.localPaths;
        if (!list || list.length === 0)
            return;
        root.selectWallpaperPath(list[Math.floor(Math.random() * list.length)]);
    }

    // Left click: download (online) and apply. Right click on an online result:
    // download into the library only, without changing the current wallpaper.
    function openItem(item, applyWallpaper = true) {
        if (typeof item === "string") {
            if (applyWallpaper)
                root.selectWallpaperPath(item);
            return;
        }
        // Wallhaven result: download full-res, then (optionally) apply it.
        Wallhaven.download(item, dest => {
            WallpaperLibrary.noteLocalAspect(dest, root.aspectFor(item));
            WallpaperLibrary.refresh();
            if (applyWallpaper)
                root.selectWallpaperPath(dest);
        }, msg => {
            Wallhaven.error = msg;
        });
    }

    Connections {
        target: WallpaperLibrary
        function onWallpapersChanged() {
            root.ensureCategory();
        }
    }

    Connections {
        target: Wallpapers
        function onChanged() {
            if (Config.options.wallpaperSelector.closeAfterSelection)
                GlobalStates.wallpaperSelectorOpen = false;
        }
    }

    // The window is kept alive after the first open (see WallpaperSelector.qml's
    // `primed` latch), so the body no longer regains active focus on its own when
    // reshown. Re-grab it on reopen so Esc/keys keep working after a close.
    Connections {
        target: GlobalStates
        function onWallpaperSelectorOpenChanged() {
            if (GlobalStates.wallpaperSelectorOpen)
                bg.forceActiveFocus();
        }
    }

    Component.onCompleted: {
        WallpaperLibrary.start();
        root.ensureCategory();
        // Persisted provider may be wallhaven; fetch once on first open.
        if (root.online && Wallhaven.results.length === 0 && !Wallhaven.loading)
            Wallhaven.search();
    }

    StyledRectangularShadow {
        target: bg
    }

    Rectangle {
        id: bg
        anchors {
            fill: parent
            margins: Appearance.sizes.elevationMargin
        }
        focus: true
        border.width: 1
        border.color: Appearance.colors.colLayer0Border
        color: Appearance.colors.colLayer0
        radius: Appearance.rounding.screenRounding + 5

        Keys.onPressed: event => {
            if (event.key === Qt.Key_Escape) {
                Wallpapers.stopPreview();
                GlobalStates.wallpaperSelectorOpen = false;
                event.accepted = true;
            }
        }

        // Background wash: flat layer2 by default, the live wallpaper blurred
        // when showBlurBackground is on (same recipe as the grid body).
        Item {
            anchors {
                fill: parent
                margins: 8
            }

            Rectangle {
                anchors.fill: parent
                radius: bg.radius - 4
                color: Appearance.colors.colLayer2
                visible: !Config.options.wallpaperSelector.showBlurBackground
            }

            StyledImage {
                id: bgImage
                anchors.fill: parent
                visible: Config.options.wallpaperSelector.showBlurBackground
                fillMode: Image.PreserveAspectCrop
                source: Config.options.wallpaperSelector.showBlurBackground ? Config.options.background.wallpaperPath : ""
                sourceSize: Qt.size(480, 480)
                layer.enabled: true
                layer.effect: OpacityMask {
                    maskSource: Rectangle {
                        width: bg.width - 16
                        height: bg.height - 16
                        radius: bg.radius - 4
                    }
                }
            }

            FastBlur {
                anchors.fill: parent
                visible: Config.options.wallpaperSelector.showBlurBackground
                source: bgImage
                radius: 48
                layer.enabled: visible
                layer.effect: OpacityMask {
                    maskSource: Rectangle {
                        width: bg.width - 16
                        height: bg.height - 16
                        radius: bg.radius - 4
                    }
                }
            }
        }

        ColumnLayout {
            id: layout
            anchors {
                fill: parent
                margins: 12
                bottomMargin: 12
            }
            spacing: 10
            z: 1

            // ---------------------------------------------------- toolbar row 1
            RowLayout {
                Layout.fillWidth: true
                spacing: 10

                MaterialSymbol {
                    text: "grid_view"
                    iconSize: Appearance.font.pixelSize.huge
                    color: Appearance.colors.colOnLayer0
                }

                StyledText {
                    text: Translation.tr("Wallpaper Switcher")
                    font.pixelSize: Appearance.font.pixelSize.large
                    color: Appearance.colors.colOnLayer0
                }

                Rectangle {
                    Layout.alignment: Qt.AlignVCenter
                    visible: GlobalStates.wallpaperSelectorTarget === "lockWall"
                    implicitWidth: targetChipText.implicitWidth + 18
                    implicitHeight: 24
                    radius: 12
                    color: Appearance.colors.colSecondaryContainer

                    StyledText {
                        id: targetChipText
                        anchors.centerIn: parent
                        text: Translation.tr("Lock screen")
                        font.pixelSize: Appearance.font.pixelSize.small
                        color: Appearance.colors.colOnSecondaryContainer
                    }
                }

                Item {
                    Layout.fillWidth: true
                }

                // Provider switch.
                RowLayout {
                    Layout.alignment: Qt.AlignVCenter
                    spacing: 4

                    RippleButton {
                        implicitWidth: 74
                        implicitHeight: 34
                        buttonRadius: 17
                        toggled: !root.online
                        colBackgroundToggled: Appearance.colors.colPrimary
                        contentItem: StyledText {
                            text: Translation.tr("Local")
                            horizontalAlignment: Text.AlignHCenter
                            font.pixelSize: Appearance.font.pixelSize.small
                            color: !root.online ? Appearance.colors.colOnPrimary : Appearance.colors.colOnLayer1
                        }
                        onClicked: root.setProvider("local")
                    }
                    RippleButton {
                        implicitWidth: 90
                        implicitHeight: 34
                        buttonRadius: 17
                        toggled: root.online
                        colBackgroundToggled: Appearance.colors.colPrimary
                        contentItem: StyledText {
                            text: Translation.tr("Wallhaven")
                            horizontalAlignment: Text.AlignHCenter
                            font.pixelSize: Appearance.font.pixelSize.small
                            color: root.online ? Appearance.colors.colOnPrimary : Appearance.colors.colOnLayer1
                        }
                        onClicked: root.setProvider("wallhaven")
                    }
                }

                // Rows stepper.
                MaterialSymbol {
                    Layout.alignment: Qt.AlignVCenter
                    text: "view_stream"
                    iconSize: Appearance.font.pixelSize.larger
                    color: Appearance.colors.colOnSurfaceVariant
                }
                RippleButton {
                    Layout.alignment: Qt.AlignVCenter
                    implicitWidth: 32
                    implicitHeight: 32
                    buttonRadius: 16
                    onClicked: root.setRows(root.rows - 1)
                    contentItem: MaterialSymbol {
                        anchors.centerIn: parent
                        text: "remove"
                        iconSize: Appearance.font.pixelSize.small
                        color: Appearance.colors.colOnLayer1
                    }
                }
                StyledText {
                    Layout.alignment: Qt.AlignVCenter
                    Layout.preferredWidth: 18
                    horizontalAlignment: Text.AlignHCenter
                    text: String(root.rows)
                    color: Appearance.colors.colOnLayer0
                }
                RippleButton {
                    Layout.alignment: Qt.AlignVCenter
                    implicitWidth: 32
                    implicitHeight: 32
                    buttonRadius: 16
                    onClicked: root.setRows(root.rows + 1)
                    contentItem: MaterialSymbol {
                        anchors.centerIn: parent
                        text: "add"
                        iconSize: Appearance.font.pixelSize.small
                        color: Appearance.colors.colOnLayer1
                    }
                }

                // Tile-size stepper.
                MaterialSymbol {
                    Layout.alignment: Qt.AlignVCenter
                    text: "photo_size_select_large"
                    iconSize: Appearance.font.pixelSize.larger
                    color: Appearance.colors.colOnSurfaceVariant
                }
                RippleButton {
                    Layout.alignment: Qt.AlignVCenter
                    implicitWidth: 32
                    implicitHeight: 32
                    buttonRadius: 16
                    onClicked: root.setTileSize(root.tileSize - 20)
                    contentItem: MaterialSymbol {
                        anchors.centerIn: parent
                        text: "remove"
                        iconSize: Appearance.font.pixelSize.small
                        color: Appearance.colors.colOnLayer1
                    }
                }
                StyledText {
                    Layout.alignment: Qt.AlignVCenter
                    Layout.preferredWidth: 40
                    horizontalAlignment: Text.AlignHCenter
                    text: root.tileSize + "px"
                    font.pixelSize: Appearance.font.pixelSize.small
                    color: Appearance.colors.colOnLayer0
                }
                RippleButton {
                    Layout.alignment: Qt.AlignVCenter
                    implicitWidth: 32
                    implicitHeight: 32
                    buttonRadius: 16
                    onClicked: root.setTileSize(root.tileSize + 20)
                    contentItem: MaterialSymbol {
                        anchors.centerIn: parent
                        text: "add"
                        iconSize: Appearance.font.pixelSize.small
                        color: Appearance.colors.colOnLayer1
                    }
                }

                // Local: random. Wallhaven: re-run search.
                RippleButton {
                    Layout.alignment: Qt.AlignVCenter
                    visible: !root.online
                    implicitWidth: 38
                    implicitHeight: 38
                    buttonRadius: 19
                    colBackground: Appearance.colors.colSecondaryContainer
                    onClicked: root.applyRandom()
                    contentItem: MaterialSymbol {
                        anchors.centerIn: parent
                        text: "casino"
                        iconSize: Appearance.font.pixelSize.larger
                        color: Appearance.colors.colOnSecondaryContainer
                    }
                    StyledToolTip {
                        text: Translation.tr("Random wallpaper in this category")
                    }
                }
                RippleButton {
                    Layout.alignment: Qt.AlignVCenter
                    visible: !root.online
                    implicitWidth: 38
                    implicitHeight: 38
                    buttonRadius: 19
                    colBackground: Appearance.colors.colSecondaryContainer
                    onClicked: WallpaperLibrary.refresh()
                    contentItem: MaterialSymbol {
                        anchors.centerIn: parent
                        text: "refresh"
                        iconSize: Appearance.font.pixelSize.larger
                        color: Appearance.colors.colOnSecondaryContainer
                    }
                    StyledToolTip {
                        text: Translation.tr("Rescan wallpapers")
                    }
                }
                RippleButton {
                    Layout.alignment: Qt.AlignVCenter
                    visible: root.online
                    implicitWidth: 38
                    implicitHeight: 38
                    buttonRadius: 19
                    colBackground: Appearance.colors.colPrimary
                    onClicked: Wallhaven.search()
                    contentItem: MaterialSymbol {
                        anchors.centerIn: parent
                        text: "search"
                        iconSize: Appearance.font.pixelSize.larger
                        color: Appearance.colors.colOnPrimary
                    }
                    StyledToolTip {
                        text: Translation.tr("Search Wallhaven")
                    }
                }
            }

            // ------------------------------------------- toolbar row 2 (online)
            RowLayout {
                Layout.fillWidth: true
                visible: root.online
                spacing: 8

                ToolbarTextField {
                    id: searchField
                    Layout.fillWidth: true
                    Layout.fillHeight: false
                    Layout.maximumWidth: 260
                    implicitHeight: 34
                    placeholderText: Translation.tr("Search Wallhaven…")
                    text: Wallhaven.query
                    onTextEdited: Wallhaven.query = text
                    onAccepted: Wallhaven.search()
                }

                // Category bits: general | anime | people.
                Repeater {
                    model: [
                        { name: "general", icon: "photo", label: "General" },
                        { name: "anime", icon: "animation", label: "Anime" },
                        { name: "people", icon: "groups", label: "People" }
                    ]
                    RippleButton {
                        required property var modelData
                        Layout.alignment: Qt.AlignVCenter
                        implicitWidth: catRow.implicitWidth + 20
                        implicitHeight: 34
                        buttonRadius: 17
                        toggled: Wallhaven.categoryBitOn(modelData.name)
                        colBackgroundToggled: Appearance.colors.colSecondaryContainer
                        colBackgroundToggledHover: Appearance.colors.colSecondaryContainerHover
                        onClicked: Wallhaven.toggleCategory(modelData.name)
                        contentItem: RowLayout {
                            id: catRow
                            anchors.centerIn: parent
                            spacing: 4
                            MaterialSymbol {
                                text: modelData.icon
                                iconSize: Appearance.font.pixelSize.small
                                color: Wallhaven.categoryBitOn(modelData.name) ? Appearance.colors.colOnSecondaryContainer : Appearance.colors.colOnLayer1
                            }
                            StyledText {
                                text: modelData.label
                                font.pixelSize: Appearance.font.pixelSize.small
                                color: Wallhaven.categoryBitOn(modelData.name) ? Appearance.colors.colOnSecondaryContainer : Appearance.colors.colOnLayer1
                            }
                        }
                    }
                }

                // Purity levels (cumulative); sketchy/nsfw gated behind key+policy.
                Repeater {
                    model: [
                        { lvl: "sfw", label: "SFW" },
                        { lvl: "sketchy", label: "Sketchy" },
                        { lvl: "nsfw", label: "NSFW" }
                    ]
                    RippleButton {
                        required property var modelData
                        Layout.alignment: Qt.AlignVCenter
                        enabled: modelData.lvl === "sfw" || Wallhaven.nsfwAllowed
                        implicitWidth: 62
                        implicitHeight: 34
                        buttonRadius: 17
                        toggled: Wallhaven.purityLvl === modelData.lvl
                        colBackgroundToggled: Appearance.colors.colTertiaryContainer
                        colBackgroundToggledHover: Appearance.colors.colTertiaryContainerHover
                        onClicked: {
                            Wallhaven.purityLvl = modelData.lvl;
                            Wallhaven.search();
                        }
                        contentItem: StyledText {
                            text: modelData.label
                            horizontalAlignment: Text.AlignHCenter
                            font.pixelSize: Appearance.font.pixelSize.small
                            color: Wallhaven.purityLvl === modelData.lvl ? Appearance.colors.colOnTertiaryContainer : Appearance.colors.colOnLayer1
                        }
                    }
                }

                // Locked-state hint: while the NSFW gate is closed (Wallhaven API
                // key missing from safe storage) the Sketchy/NSFW buttons above
                // are disabled — surface *why* with a hoverable lock icon instead
                // of dropping the user on two dead buttons. A separate MouseArea
                // is required because disabled buttons don't receive hover.
                Item {
                    Layout.alignment: Qt.AlignVCenter
                    implicitWidth: 20
                    implicitHeight: 20
                    visible: !Wallhaven.nsfwAllowed

                    MaterialSymbol {
                        anchors.centerIn: parent
                        text: "lock"
                        iconSize: Appearance.font.pixelSize.small
                        color: Appearance.colors.colOnSurfaceVariant
                    }
                    MouseArea {
                        id: purityLockHintHover
                        anchors.fill: parent
                        hoverEnabled: true
                        acceptedButtons: Qt.NoButton
                        cursorShape: Qt.ArrowCursor
                    }
                    StyledToolTip {
                        extraVisibleCondition: false
                        alternativeVisibleCondition: purityLockHintHover.containsMouse
                        text: Translation.tr("Add a Wallhaven API key (/wallhaven in the launcher) to unlock Sketchy/NSFW")
                    }
                }

                StyledComboBox {
                    Layout.fillWidth: false
                    Layout.preferredWidth: 132
                    Layout.alignment: Qt.AlignVCenter
                    model: Wallhaven.sortingOptions
                    textRole: "label"
                    Component.onCompleted: {
                        const i = Wallhaven.sortingOptions.findIndex(o => o.value === Wallhaven.sorting);
                        if (i >= 0)
                            currentIndex = i;
                    }
                    onActivated: Wallhaven.setSorting(Wallhaven.sortingOptions[currentIndex].value)
                }

                StyledComboBox {
                    Layout.fillWidth: false
                    Layout.preferredWidth: 104
                    Layout.alignment: Qt.AlignVCenter
                    model: Wallhaven.resolutionOptions
                    textRole: "label"
                    Component.onCompleted: {
                        const i = Wallhaven.resolutionOptions.findIndex(o => o.value === Wallhaven.atleast);
                        if (i >= 0)
                            currentIndex = i;
                    }
                    onActivated: {
                        Wallhaven.atleast = Wallhaven.resolutionOptions[currentIndex].value;
                        Wallhaven.search();
                    }
                }

                // Pagination.
                RippleButton {
                    Layout.alignment: Qt.AlignVCenter
                    enabled: Wallhaven.page > 1 && !Wallhaven.loading
                    implicitWidth: 34
                    implicitHeight: 34
                    buttonRadius: 17
                    onClicked: Wallhaven.prevPage()
                    contentItem: MaterialSymbol {
                        anchors.centerIn: parent
                        text: "chevron_left"
                        iconSize: Appearance.font.pixelSize.larger
                        color: Appearance.colors.colOnLayer1
                    }
                }
                StyledText {
                    Layout.alignment: Qt.AlignVCenter
                    Layout.preferredWidth: 54
                    horizontalAlignment: Text.AlignHCenter
                    text: Wallhaven.loading ? "…" : `${Wallhaven.page} / ${Wallhaven.lastPage}`
                    font.pixelSize: Appearance.font.pixelSize.small
                    color: Appearance.colors.colSubtext
                }
                RippleButton {
                    Layout.alignment: Qt.AlignVCenter
                    enabled: Wallhaven.page < Wallhaven.lastPage && !Wallhaven.loading
                    implicitWidth: 34
                    implicitHeight: 34
                    buttonRadius: 17
                    onClicked: Wallhaven.nextPage()
                    contentItem: MaterialSymbol {
                        anchors.centerIn: parent
                        text: "chevron_right"
                        iconSize: Appearance.font.pixelSize.larger
                        color: Appearance.colors.colOnLayer1
                    }
                }
            }

            // --------------------------------------------------------- strip
            Flickable {
                id: strip
                Layout.fillWidth: true
                Layout.fillHeight: true
                clip: true
                contentWidth: masonry.contentWidth
                // Natural height = the masonry's own height. The panel hugs the
                // content (see `idealHeight`) so the strip is usually exactly
                // this tall; if the panel is clamped below it, the overflow
                // scrolls.
                implicitHeight: masonry.implicitHeight
                contentHeight: masonry.implicitHeight
                flickableDirection: Flickable.HorizontalAndVerticalFlick
                boundsBehavior: Flickable.StopAtBounds

                onContentXChanged: {
                    // Infinite-ish scroll: pull the next Wallhaven page when the
                    // tail comes into view.
                    if (root.online && contentWidth > width
                            && contentX + width >= contentWidth - 600)
                        Wallhaven.nextPage();
                }

                // Wheel → horizontal scroll. NoButton so tile clicks fall
                // through (same pattern as StyledFlickable's overlay).
                MouseArea {
                    anchors.fill: parent
                    acceptedButtons: Qt.NoButton
                    onWheel: wheel => {
                        const delta = wheel.angleDelta.y !== 0 ? wheel.angleDelta.y : wheel.angleDelta.x;
                        strip.contentX = Math.max(0, Math.min(
                            strip.contentX - delta,
                            Math.max(0, strip.contentWidth - strip.width)));
                        wheel.accepted = true;
                    }
                }

                AppMasonryRow {
                    id: masonry
                    // AppMasonryRow is layout-only: its `height` defaults to 0
                    // (implicitHeight is not applied by plain anchors), so
                    // `verticalCenter` would pin a 0-height box to the middle
                    // and push the tiles into the lower half. Give it its real
                    // height and centre that instead.
                    y: Math.max(0, (strip.height - implicitHeight) / 2)
                    height: implicitHeight
                    // Contract: explicit Flickable width, never parent.width of
                    // the viewport (0-width wedge). Widths/heights derive from
                    // settings only, so no content<->viewport negotiation loop.
                    width: strip.width
                    rows: root.rows
                    rowHeight: root.tileSize
                    spacing: 4
                    // Stable list order left-to-right (aspect only sizes tiles);
                    // shortest-row packing would visibly reshuffle on decode.
                    balanceRows: false
                    model: root.currentModel
                    aspectRatio: item => root.aspectFor(item)
                    viewLeft: strip.contentX - 800
                    viewRight: strip.contentX + strip.width + 800
                    placeholder: Component {
                        Rectangle {
                            property var modelData
                            radius: Appearance.rounding.normal
                            color: Appearance.colors.colLayer2
                        }
                    }
                    delegate: Component {
                        Item {
                            id: tile
                            property var modelData
                            readonly property bool isRemote: typeof modelData === "object" && modelData !== null
                            readonly property string filePath: tile.isRemote ? "" : modelData
                            readonly property bool isVideo: root.isVideoItem(modelData)
                            readonly property bool isDownloading: tile.isRemote && Wallhaven.downloadingId === modelData.id
                            width: masonry.widthFor(modelData)
                            height: masonry.rowHeight

                            Rectangle {
                                id: tileSurface
                                anchors.fill: parent
                                radius: Appearance.rounding.normal
                                color: Appearance.colors.colLayer2
                                clip: true

                                // Plain Image (not StyledImage): StyledImage fades
                                // in from opacity 0 on every decode, which reads
                                // as a reload. With the panel now persistent the
                                // tiles are only decoded once anyway, but the
                                // fade would still replay on the first open, so
                                // drop it and let each tile appear the moment it
                                // is ready.
                                Image {
                                    id: tileImage
                                    anchors.fill: parent
                                    source: root.tileSource(modelData)
                                    fillMode: Image.PreserveAspectCrop
                                    asynchronous: true
                                    cache: true
                                    retainWhileLoading: true
                                    sourceSize.width: Math.max(64, Math.round(tile.width * 1.5))
                                    sourceSize.height: Math.max(64, Math.round(tile.height * 1.5))
                                    onStatusChanged: {
                                        // Local only: paintedWidth/Height preserve
                                        // natural aspect under PreserveAspectCrop;
                                        // feed it back so the tile resizes to match.
                                        if (!tile.isRemote && tile.filePath && status === Image.Ready
                                                && paintedWidth > 0 && paintedHeight > 0)
                                            WallpaperLibrary.noteLocalAspect(tile.filePath, paintedWidth / paintedHeight);
                                    }
                                }

                                // Placeholder only for the cases that genuinely
                                // need a glyph: missing video thumb, or an online
                                // result not yet downloaded. Local stills just sit
                                // on the flat surface colour until decoded (no
                                // "image" icon flash).
                                MaterialSymbol {
                                    anchors.centerIn: parent
                                    visible: tileImage.status !== Image.Ready
                                        && (tile.isVideo || tile.isRemote)
                                    text: tile.isVideo ? "movie" : "cloud_download"
                                    iconSize: Appearance.font.pixelSize.huge
                                    color: Appearance.colors.colSubtext
                                }

                                // Play glyph over video thumbs.
                                Rectangle {
                                    visible: tile.isVideo && tileImage.status === Image.Ready
                                    anchors {
                                        left: parent.left
                                        bottom: parent.bottom
                                        margins: 6
                                    }
                                    implicitWidth: 24
                                    implicitHeight: 24
                                    radius: 12
                                    color: ColorUtils.transparentize("black", 0.35)
                                    MaterialSymbol {
                                        anchors.centerIn: parent
                                        text: "play_arrow"
                                        iconSize: Appearance.font.pixelSize.normal
                                        color: "white"
                                        fill: 1
                                    }
                                }

                                // Resolution chip for online results — only while
                                // the pointer is over this tile, so the strip
                                // stays clean (info on hover, not on every tile).
                                Rectangle {
                                    visible: hit.containsMouse && tile.isRemote
                                        && modelData.resolution !== undefined
                                        && String(modelData.resolution).length > 0
                                    anchors {
                                        right: parent.right
                                        bottom: parent.bottom
                                        margins: 6
                                    }
                                    implicitWidth: resText.implicitWidth + 12
                                    implicitHeight: 20
                                    radius: 10
                                    color: ColorUtils.transparentize("black", 0.35)
                                    StyledText {
                                        id: resText
                                        anchors.centerIn: parent
                                        text: tile.isRemote ? String(modelData.resolution) : ""
                                        font.pixelSize: Appearance.font.pixelSize.smaller
                                        color: "white"
                                    }
                                }

                                // Download spinner overlay.
                                Rectangle {
                                    anchors.fill: parent
                                    visible: tile.isDownloading
                                    color: ColorUtils.transparentize("black", 0.45)
                                    MaterialLoadingIndicator {
                                        anchors.centerIn: parent
                                        loading: true
                                        implicitSize: 32
                                    }
                                }
                            }

                            Rectangle {
                                anchors.fill: parent
                                radius: Appearance.rounding.normal
                                color: "transparent"
                                visible: !tile.isRemote && tile.filePath === root.currentWallpaper
                                border.width: 2
                                border.color: Appearance.colors.colPrimary
                            }

                            MouseArea {
                                id: hit
                                anchors.fill: parent
                                hoverEnabled: true
                                acceptedButtons: Qt.LeftButton | Qt.RightButton
                                cursorShape: Qt.PointingHandCursor
                                // Online results: left = download + apply,
                                // right = download into the library only.
                                // Local tiles keep the single left-click apply.
                                onClicked: mouse => {
                                    if (tile.isRemote)
                                        root.openItem(modelData, mouse.button !== Qt.RightButton);
                                    else if (mouse.button === Qt.LeftButton)
                                        root.openItem(modelData, true);
                                }

                                Rectangle {
                                    anchors.fill: parent
                                    radius: Appearance.rounding.normal
                                    color: Appearance.colors.colPrimary
                                    opacity: hit.containsMouse ? 0.14 : 0
                                    Behavior on opacity {
                                        NumberAnimation { duration: 120 }
                                    }
                                }

                                // Parent is a MouseArea, whose `hovered` the
                                // shared StyledToolTip cannot key off (see the
                                // codebase pattern: ContentSubsection, AiChat,
                                // ApiInputBoxIndicator all switch to the
                                // alternative condition inside a MouseArea).
                                // Without this every tile rendered its tooltip
                                // permanently — the whole strip looked labelled.
                                StyledToolTip {
                                    extraVisibleCondition: false
                                    alternativeVisibleCondition: hit.containsMouse
                                    text: tile.isRemote
                                        ? (modelData.resolution + " · " + modelData.id + "\n" + Translation.tr("Left-click: apply · Right-click: download only"))
                                        : tile.filePath
                                }
                            }
                        }
                    }
                }

                // Empty / loading / error states.
                ColumnLayout {
                    anchors.centerIn: parent
                    spacing: 8
                    visible: root.currentModel.length === 0

                    MaterialLoadingIndicator {
                        Layout.alignment: Qt.AlignHCenter
                        visible: root.stripBusy
                        loading: root.stripBusy
                        implicitSize: 40
                    }
                    StyledText {
                        Layout.alignment: Qt.AlignHCenter
                        visible: !root.stripBusy
                        text: {
                            if (root.online)
                                return root.onlineError
                                    ? Wallhaven.error
                                    : Translation.tr("No results — press search to fetch wallpapers");
                            return root.libraryEmpty
                                ? Translation.tr("Scanning wallpapers…")
                                : Translation.tr("No wallpapers in this category");
                        }
                        color: root.onlineError ? Appearance.colors.colError : Appearance.colors.colSubtext
                    }
                }
            }

            // Category dropdown lives under the strip for local mode only.
            RowLayout {
                Layout.fillWidth: true
                visible: !root.online
                spacing: 8

                StyledComboBox {
                    id: categoryCombo
                    Layout.fillWidth: false
                    Layout.preferredWidth: 240
                    implicitHeight: 34
                    model: root.categories.map(key => ({
                        key: key,
                        label: root.categoryLabel(key)
                    }))
                    textRole: "label"
                    onActivated: root.selectedCategory = root.categories[currentIndex]
                }

                StyledText {
                    Layout.alignment: Qt.AlignVCenter
                    text: `${root.localPaths.length} ${Translation.tr("wallpapers")}`
                    font.pixelSize: Appearance.font.pixelSize.small
                    color: Appearance.colors.colSubtext
                }

                Item {
                    Layout.fillWidth: true
                }
            }
        }
    }
}
