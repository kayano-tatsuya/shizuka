import qs.services
import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io

/**
 * Detail card for one booru image, meant to live inside a PopupWindow docked to
 * the right edge of the left sidebar (the AE "BooruDialog" behaviour).
 *
 * It presents the image, its metadata and tags, and every per-image action —
 * including "set as sidebar waifu". The viewer owns the shared state (which
 * image is open, the bookmark list, the current waifu), so this file reports
 * intent back with signals and only performs the self-contained actions
 * (download / wallpaper / open / copy) itself, matching `BooruTile`.
 */
Rectangle {
    id: root

    property var image
    property bool allowNsfw: false
    property bool bookmarked: false
    property bool isWaifu: false
    readonly property bool pinned: {
        const pins = (Persistent.states.booru.pins) || [];
        const id = root.image?.id;
        const prov = root.image?.provider ?? (root.image?.api && root.image.api.value) ?? "";
        if (id === undefined || id === null) return false;
        return pins.some(p => p && String(p.id) === String(id) && ((p.provider ?? (p.api && p.api.value) ?? "") === prov));
    }

    signal closeRequested()
    signal toggleBookmarkRequested()
    signal setWaifuRequested()
    signal tagActivated(string tag)

    color: Appearance.colors.colLayer0
    radius: Appearance.rounding.normal
    border.width: 1
    border.color: ColorUtils.transparentize(Appearance.colors.colLayer0Border, 0.8)

    readonly property bool gated: (image?.is_nsfw ?? false) && !root.allowNsfw
    readonly property real imageAspect: {
        const w = root.image?.width ?? 0;
        const h = root.image?.height ?? 0;
        if (w > 0 && h > 0) return h / w;
        return 0.62;
    }
    readonly property string fullUrl: image?.file_url ?? image?.sample_url ?? ""
    readonly property string displayUrl: image?.sample_url ?? image?.file_url ?? image?.preview_url ?? ""
    readonly property string sourceUrl: image?.source ?? ""
    // Gelbooru hotlink-protects its image CDN: downloads need a Referer.
    readonly property string imageReferer: image?.imageReferer ?? ""
    // Referer-protected hosts (Gelbooru) hotlink-protect their CDN: QML's
    // Image cannot send a Referer header, so pull the preview through curl
    // into the cache and display the local copy (mirrors BooruTile).
    readonly property string remoteThumb: root.image?.preview_url ?? root.image?.sample_url ?? ""
    readonly property var remoteThumbFallbacks: {
        const list = [];
        if (root.image?.sample_url) list.push(root.image.sample_url);
        if (root.image?.file_url) list.push(root.image.file_url);
        if (root.image?.preview_url) list.push(root.image.preview_url);
        return list;
    }
    readonly property bool fetchThumb: root.imageReferer.length > 0 && root.remoteThumb.length > 0
    readonly property string thumbCachePath: {
        if (root.remoteThumb.length === 0) return "";
        const base = decodeURIComponent(root.remoteThumb.substring(root.remoteThumb.lastIndexOf('/') + 1));
        return base.length > 0 ? `${Directories.booruPreviews}/${base}` : "";
    }
    property string localThumbPath: ""
    property bool thumbFetchStarted: false
    property bool thumbFetchFailed: false

    function fetchThumbnail() {
        if (!root.fetchThumb || root.gated || root.thumbFetchStarted) return;
        root.thumbFetchStarted = true;
        const dir = StringUtils.shellSingleQuoteEscape(Directories.booruPreviews);
        const file = StringUtils.shellSingleQuoteEscape(root.thumbCachePath);
        const url = StringUtils.shellSingleQuoteEscape(root.remoteThumb);
        const referer = StringUtils.shellSingleQuoteEscape(root.imageReferer);
        const ua = Config.options?.networking?.userAgent ?? "";
        const uaArg = ua ? ` -H 'User-Agent: ${StringUtils.shellSingleQuoteEscape(ua)}'` : "";
        thumbFetch.command = ["bash", "-c",
            `mkdir -p '${dir}' && { [ -s '${file}' ] || curl -fsSL --max-time 15 -H 'Referer: ${referer}'${uaArg} '${url}' -o '${file}'; } && [ -s '${file}' ]`];
        thumbFetch.running = true;
    }
    onImageChanged: {
        root.thumbFetchStarted = false;
        root.localThumbPath = "";
        root.thumbFetchFailed = false;
        root.fetchThumbnail();
    }
    onGatedChanged: if (!root.gated) root.fetchThumbnail()
    Component.onCompleted: root.fetchThumbnail()

    Process {
        id: thumbFetch
        onExited: (exitCode) => {
            if (exitCode === 0 && root.thumbCachePath.length > 0) {
                root.localThumbPath = root.thumbCachePath;
            } else {
                root.thumbFetchFailed = true;
            }
        }
    }

    readonly property var tagList: String(image?.tags ?? "").split(/\s+/).filter(tag => tag.length > 0)

    readonly property string ratingLabel: {
        switch ((root.image?.rating ?? "").toLowerCase()) {
        case "s": case "safe": case "general": return Translation.tr("Safe");
        case "q": case "questionable": case "sensitive": return Translation.tr("Questionable");
        case "e": case "explicit": return Translation.tr("Explicit");
        default: return "";
        }
    }
    readonly property color ratingColor: {
        switch ((root.image?.rating ?? "").toLowerCase()) {
        case "q": case "questionable": case "sensitive": return Appearance.colors.colTertiaryContainer;
        case "e": case "explicit": return Appearance.colors.colErrorContainer;
        default: return Appearance.colors.colSecondaryContainer;
        }
    }

    function openUrl(url) {
        if (!url || url.length === 0) return;
        Hyprland.dispatch("hl.config({cursor = {no_warps = true}})");
        Qt.openUrlExternally(url);
        Hyprland.dispatch("hl.config({cursor = {no_warps = false}})");
    }

    function download() {
        if (root.fullUrl.length === 0) return;
        const target = image?.is_nsfw ? Directories.booruDownloadsNsfw : Directories.booruDownloads;
        const name = decodeURIComponent(root.fullUrl.substring(root.fullUrl.lastIndexOf('/') + 1))
            || ("booru_" + (image?.id ?? Date.now()));
        const ua = Config.options?.networking?.userAgent ?? "";
        const uaArg = ua ? ` -H 'User-Agent: ${StringUtils.shellSingleQuoteEscape(ua)}'` : "";
        const refererArg = root.imageReferer
            ? ` -H 'Referer: ${StringUtils.shellSingleQuoteEscape(root.imageReferer)}'` : "";
        Quickshell.execDetached(["bash", "-c",
            `mkdir -p '${StringUtils.shellSingleQuoteEscape(target)}' && curl -fsSL '${StringUtils.shellSingleQuoteEscape(root.fullUrl)}'${uaArg}${refererArg} -o '${StringUtils.shellSingleQuoteEscape(target + "/" + name)}' && notify-send '${Translation.tr("Download complete")}' '${StringUtils.shellSingleQuoteEscape(target + "/" + name)}' -a 'Shell'`
        ]);
    }

    // Download straight into the wallpapers folder, then hand it to the usual
    // wallpaper pipeline (same flow as WaifuWidget's "set as wallpaper").
    Process {
        id: wallpaperFetch
        property string target: ""
        onExited: (code) => {
            if (code !== 0) return;
            Wallpapers.apply(wallpaperFetch.target);
        }
    }

    function saveWallpaper() {
        if (root.fullUrl.length === 0) return;
        const name = decodeURIComponent(root.fullUrl.substring(root.fullUrl.lastIndexOf('/') + 1))
            || ("booru_" + (image?.id ?? Date.now()));
        const dir = Directories.waifuDownloads;
        const target = `${dir}/${name}`;
        const ua = Config.options?.networking?.userAgent ?? "";
        const uaArg = ua ? ` -H 'User-Agent: ${StringUtils.shellSingleQuoteEscape(ua)}'` : "";
        const refererArg = root.imageReferer
            ? ` -H 'Referer: ${StringUtils.shellSingleQuoteEscape(root.imageReferer)}'` : "";
        wallpaperFetch.target = target;
        wallpaperFetch.command = ["bash", "-c",
            `mkdir -p '${StringUtils.shellSingleQuoteEscape(dir)}' && curl -fsSL '${StringUtils.shellSingleQuoteEscape(root.fullUrl)}'${uaArg}${refererArg} -o '${StringUtils.shellSingleQuoteEscape(target)}'`];
        wallpaperFetch.running = true;
    }

    function togglePinned() {
        if (!root.image) return;
        const img = root.image;
        const apiValue = Booru.currentProvider || img.provider || (img.api && img.api.value) || "";
        const extRaw = (img.extension || "").toLowerCase();
        const urlExt = (img.file_url || img.sample_url || img.preview_url || "").split('.').pop().split('?')[0].toLowerCase();
        const ext = (extRaw && extRaw !== "jpg" ? extRaw : (urlExt && urlExt.length <= 5 ? urlExt : "jpg"));
        const pins = ((Persistent.states.booru.pins) || []).slice();
        const idx = pins.findIndex(p => p && String(p.id) === String(img.id) && ((p.provider ?? "") === apiValue));
        if (idx >= 0) {
            pins.splice(idx, 1);
        } else {
            pins.unshift(Object.assign({}, img, { provider: apiValue, extension: ext }));
        }
        Persistent.states.booru.pins = pins;
        FastfetchPins.scheduleSync();
    }

    component DetailAction: RippleButton {
        id: action
        required property string symbol
        required property string label
        property bool active: false
        signal triggered()

        implicitHeight: 38
        buttonRadius: Appearance.rounding.small
        toggled: action.active
        colBackground: Appearance.colors.colLayer2
        colBackgroundHover: Appearance.colors.colLayer2Hover
        colBackgroundToggled: Appearance.colors.colPrimaryContainer
        colBackgroundToggledHover: Appearance.colors.colPrimaryContainerHover
        onClicked: action.triggered()
        contentItem: RowLayout {
            spacing: 6
            MaterialSymbol {
                Layout.leftMargin: 10
                text: action.symbol
                iconSize: Appearance.font.pixelSize.normal
                color: action.active ? Appearance.colors.colOnPrimaryContainer : Appearance.colors.colOnLayer1
            }
            StyledText {
                Layout.fillWidth: true
                Layout.rightMargin: 10
                text: action.label
                elide: Text.ElideRight
                color: action.active ? Appearance.colors.colOnPrimaryContainer : Appearance.colors.colOnLayer1
                font.pixelSize: Appearance.font.pixelSize.small
            }
        }
    }

    component TagChip: Rectangle {
        id: chip
        required property string tag
        implicitWidth: Math.min(220, chipLabel.implicitWidth + 16)
        implicitHeight: 24
        radius: height / 2
        color: chipMouse.containsMouse ? Appearance.colors.colLayer2Hover : Appearance.colors.colLayer2

        StyledText {
            id: chipLabel
            anchors.centerIn: parent
            width: Math.min(chipLabel.implicitWidth, chip.width - 16)
            text: chip.tag
            elide: Text.ElideRight
            color: Appearance.colors.colOnLayer1
            font.pixelSize: Appearance.font.pixelSize.smaller
        }
        MouseArea {
            id: chipMouse
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: root.tagActivated(chip.tag)
        }
    }

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: 12
        spacing: 10

        // ---- header ------------------------------------------------------
        RowLayout {
            Layout.fillWidth: true
            spacing: 8

            StyledText {
                text: root.image?.id !== undefined ? ("#" + root.image.id) : Translation.tr("Image")
                color: Appearance.colors.colOnLayer1
                font.pixelSize: Appearance.font.pixelSize.large
                font.weight: Font.DemiBold
            }
            Rectangle {
                visible: root.ratingLabel.length > 0
                implicitWidth: ratingText.implicitWidth + 14
                implicitHeight: 20
                radius: height / 2
                color: root.ratingColor
                StyledText {
                    id: ratingText
                    anchors.centerIn: parent
                    text: root.ratingLabel
                    color: Appearance.colors.colOnLayer1
                    font.pixelSize: Appearance.font.pixelSize.smaller
                }
            }
            Item { Layout.fillWidth: true }
            RippleButton {
                implicitWidth: 32
                implicitHeight: 32
                buttonRadius: Appearance.rounding.full
                colBackground: "transparent"
                colBackgroundHover: Appearance.colors.colLayer2Hover
                onClicked: root.closeRequested()
                contentItem: MaterialSymbol {
                    horizontalAlignment: Text.AlignHCenter
                    verticalAlignment: Text.AlignVCenter
                    text: "close"
                    iconSize: Appearance.font.pixelSize.large
                    color: Appearance.colors.colOnLayer1
                }
                StyledToolTip { text: Translation.tr("Close") }
            }
        }

        StyledText {
            Layout.fillWidth: true
            visible: root.image !== null && root.image !== undefined && (root.image.width > 0 && root.image.height > 0)
            text: root.image ? (root.image.width + " × " + root.image.height) : ""
            color: Appearance.colors.colSubtext
            font.pixelSize: Appearance.font.pixelSize.smaller
        }

        // ---- image -------------------------------------------------------
        Rectangle {
            Layout.fillWidth: true
            // Scale the preview to the image's aspect ratio (like the right
            // sidebar's waifu banner) instead of a fixed 240 px strip, so
            // portrait/landscape art is not squashed or letterboxed.
            Layout.preferredHeight: Math.max(160, Math.min(460, (root.width - 24) * root.imageAspect))
            radius: Appearance.rounding.small
            color: Appearance.colors.colLayer2
            clip: true

            StyledImage {
                id: preview
                anchors.fill: parent
                fillMode: Image.PreserveAspectFit
                source: root.gated ? "" : (root.fetchThumb
                    ? (root.thumbFetchFailed ? root.displayUrl : root.localThumbPath)
                    : root.displayUrl)
                fallbacks: root.fetchThumb ? [] : root.remoteThumbFallbacks
                sourceSize.width: Math.max(1, width) * 2
            }

            // Loading / failure feedback so a slow (or stalled) preview never
            // reads as "infinitely loading": the StyledImage fades in only once
            // it is Ready, so without this the area looks blank in the meantime.
            ColumnLayout {
                anchors.centerIn: parent
                spacing: 4
                visible: !root.gated && !root.thumbFetchFailed && preview.status !== Image.Ready && root.displayUrl.length > 0
                MaterialLoadingIndicator {
                    Layout.alignment: Qt.AlignHCenter
                    visible: preview.status === Image.Loading || preview.status === Image.Null
                    implicitSize: 32
                }
                StyledText {
                    Layout.alignment: Qt.AlignHCenter
                    visible: preview.status === Image.Error || root.thumbFetchFailed
                    text: Translation.tr("Failed to load image")
                    color: Appearance.colors.colOnLayer1
                    font.pixelSize: Appearance.font.pixelSize.smaller
                }
            }

            // NSFW gate, matching the grid tile: no decoding of the real image.
            Rectangle {
                anchors.fill: parent
                visible: root.gated
                color: ColorUtils.transparentize(Appearance.colors.colLayer0, 0.2)

                ColumnLayout {
                    anchors.centerIn: parent
                    spacing: 4
                    MaterialSymbol {
                        Layout.alignment: Qt.AlignHCenter
                        text: "visibility_off"
                        iconSize: 32
                        color: Appearance.colors.colOnLayer1
                    }
                    StyledText {
                        Layout.alignment: Qt.AlignHCenter
                        text: Translation.tr("NSFW hidden")
                        color: Appearance.colors.colOnLayer1
                        font.pixelSize: Appearance.font.pixelSize.smaller
                    }
                }
            }
        }

        // ---- tags --------------------------------------------------------
        StyledFlickable {
            Layout.fillWidth: true
            Layout.fillHeight: true
            visible: root.tagList.length > 0
            clip: true
            contentWidth: width
            contentHeight: tagFlow.height
            boundsBehavior: Flickable.StopAtBounds

            Flow {
                id: tagFlow
                width: parent.width
                spacing: 4
                Repeater {
                    model: root.tagList
                    delegate: TagChip {
                        required property string modelData
                        tag: modelData
                    }
                }
            }
        }

        // ---- actions -----------------------------------------------------
        GridLayout {
            Layout.fillWidth: true
            columns: 2
            rowSpacing: 6
            columnSpacing: 6

            DetailAction {
                Layout.fillWidth: true
                symbol: root.isWaifu ? "favorite" : "favorite_border"
                label: root.isWaifu ? Translation.tr("Unset waifu") : Translation.tr("Set as waifu")
                active: root.isWaifu
                onTriggered: root.setWaifuRequested()
            }
            DetailAction {
                Layout.fillWidth: true
                symbol: root.bookmarked ? "bookmark_added" : "bookmark_add"
                label: root.bookmarked ? Translation.tr("Bookmarked") : Translation.tr("Bookmark")
                active: root.bookmarked
                onTriggered: root.toggleBookmarkRequested()
            }
            DetailAction {
                Layout.fillWidth: true
                symbol: root.pinned ? "push_pin" : "push_pin"
                label: root.pinned ? Translation.tr("Pinned to terminal") : Translation.tr("Pin to terminal")
                active: root.pinned
                onTriggered: root.togglePinned()
            }
            DetailAction {
                Layout.fillWidth: true
                symbol: "download"
                label: Translation.tr("Download")
                onTriggered: root.download()
            }
            DetailAction {
                Layout.fillWidth: true
                symbol: "wallpaper"
                label: Translation.tr("Set wallpaper")
                onTriggered: root.saveWallpaper()
            }
            DetailAction {
                Layout.fillWidth: true
                symbol: "open_in_new"
                label: Translation.tr("Open image")
                onTriggered: root.openUrl(root.fullUrl)
            }
            DetailAction {
                Layout.fillWidth: true
                visible: root.sourceUrl.length > 0
                symbol: "link"
                label: Translation.tr("Go to source")
                onTriggered: root.openUrl(root.sourceUrl)
            }
            DetailAction {
                Layout.fillWidth: true
                Layout.columnSpan: 2
                symbol: "content_copy"
                label: Translation.tr("Copy image link")
                onTriggered: Quickshell.clipboardText = root.fullUrl
            }
        }
    }
}
