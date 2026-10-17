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
 * One masonry cell in the booru viewer grid.
 *
 * Layout contract (see AppMasonry): `imageData` is a plain property and the
 * tile declares an explicit height derived from the image aspect ratio.
 *
 * Left click activates the tile (viewer decides what that means). The hover
 * veil exposes the per-image actions: bookmark, download, open, source, copy.
 * NSFW images stay behind a gate unless the viewer says NSFW is allowed.
 */
Rectangle {
    id: root

    property var imageData
    property bool bookmarked: false
    property bool isWaifu: false
    property bool allowNsfw: false

    signal activate()
    signal toggleBookmark()
    signal setWaifu()

    readonly property bool isVideo: ["mp4", "webm", "mkv", "gif"].includes(((imageData?.file_ext) || "").toLowerCase())
    readonly property bool gated: (imageData?.is_nsfw ?? false) && !root.allowNsfw
    readonly property real aspectRatio: (imageData && imageData.width > 0 && imageData.height > 0)
        ? imageData.height / imageData.width : 1.0

    readonly property string effectiveUrl: imageData?.file_url ?? imageData?.sample_url ?? ""

    // Some hosts (Gelbooru) hotlink-protect their image CDN: without a matching
    // Referer the request 302s to an HTML page instead of the image, and QML's
    // Image cannot send request headers. When the service tags an image with a
    // referer we therefore pull the thumbnail through curl into the preview
    // cache and display the local copy. Empty referer = load it directly.
    readonly property string imageReferer: root.imageData?.imageReferer ?? ""
    readonly property string remoteThumb: root.imageData?.preview_url ?? root.imageData?.sample_url ?? ""
    readonly property var remoteThumbFallbacks: {
        const list = [];
        if (root.imageData?.sample_url) list.push(root.imageData.sample_url);
        if (root.imageData?.file_url) list.push(root.imageData.file_url);
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

    function fetchThumbnail() {
        if (!root.fetchThumb || root.gated || root.thumbFetchStarted) return;
        root.thumbFetchStarted = true;
        const dir = StringUtils.shellSingleQuoteEscape(Directories.booruPreviews);
        const file = StringUtils.shellSingleQuoteEscape(root.thumbCachePath);
        const url = StringUtils.shellSingleQuoteEscape(root.remoteThumb);
        const referer = StringUtils.shellSingleQuoteEscape(root.imageReferer);
        const ua = Config.options?.networking?.userAgent ?? "";
        const uaArg = ua ? ` -H 'User-Agent: ${StringUtils.shellSingleQuoteEscape(ua)}'` : "";
        // `[ -s file ] ||` reuses an already-cached preview; the trailing
        // `[ -s file ]` rejects partial/empty downloads so a failed fetch never
        // looks like a successful one.
        thumbFetch.command = ["bash", "-c",
            `mkdir -p '${dir}' && { [ -s '${file}' ] || curl -fsSL -H 'Referer: ${referer}'${uaArg} '${url}' -o '${file}'; } && [ -s '${file}' ]`]
        thumbFetch.running = true;
    }

    onImageDataChanged: root.fetchThumbnail()
    onGatedChanged: if (!root.gated) root.fetchThumbnail()
    Component.onCompleted: root.fetchThumbnail()

    Process {
        id: thumbFetch
        onExited: (exitCode) => {
            if (exitCode === 0 && root.thumbCachePath.length > 0)
                root.localThumbPath = root.thumbCachePath;
        }
    }

    width: parent ? parent.width : 0
    height: Math.max(90, Math.round(width * aspectRatio))
    color: Appearance.colors.colLayer2
    radius: Appearance.rounding.small
    clip: true

    function openUrl(url) {
        if (!url || url.length === 0) return;
        Hyprland.dispatch("hl.config({cursor = {no_warps = true}})");
        Qt.openUrlExternally(url);
        Hyprland.dispatch("hl.config({cursor = {no_warps = false}})");
    }

    function download() {
        const target = imageData?.is_nsfw ? Directories.booruDownloadsNsfw : Directories.booruDownloads;
        const name = decodeURIComponent((effectiveUrl).substring((effectiveUrl).lastIndexOf('/') + 1)) || ("booru_" + (imageData?.id ?? Date.now()));
        const ua = Config.options?.networking?.userAgent ?? "";
        const uaArg = ua ? ` -H 'User-Agent: ${StringUtils.shellSingleQuoteEscape(ua)}'` : "";
        const refererArg = root.imageReferer
            ? ` -H 'Referer: ${StringUtils.shellSingleQuoteEscape(root.imageReferer)}'` : "";
        Quickshell.execDetached(["bash", "-c",
            `mkdir -p '${target}' && curl -fsSL '${StringUtils.shellSingleQuoteEscape(effectiveUrl)}'${uaArg}${refererArg} -o '${target}/${name}' && notify-send '${Translation.tr("Download complete")}' '${target}/${name}' -a 'Shell'`
        ]);
    }

    StyledImage {
        id: thumb
        anchors.fill: parent
        fillMode: Image.PreserveAspectCrop
        source: root.fetchThumb ? root.localThumbPath : root.remoteThumb
        fallbacks: root.fetchThumb ? [] : root.remoteThumbFallbacks
    }

    // NSFW gate: opaque cover, no decoding of the real image is relied upon.
    Rectangle {
        anchors.fill: parent
        visible: root.gated
        color: ColorUtils.transparentize(Appearance.colors.colLayer0, 0.25)

        ColumnLayout {
            anchors.centerIn: parent
            spacing: 2
            MaterialSymbol {
                Layout.alignment: Qt.AlignHCenter
                text: "visibility_off"
                iconSize: Appearance.font.pixelSize.huge ?? 28
                color: Appearance.colors.colOnLayer1
            }
            StyledText {
                Layout.alignment: Qt.AlignHCenter
                text: Translation.tr("NSFW")
                color: Appearance.colors.colOnLayer1
                font.pixelSize: Appearance.font.pixelSize.smaller
            }
        }
    }

    // Always-visible bookmark marker.
    MaterialSymbol {
        visible: root.bookmarked
        anchors {
            top: parent.top
            right: parent.right
            margins: 6
        }
        text: "bookmark"
        iconSize: Appearance.font.pixelSize.large
        color: Appearance.colors.colPrimary
        style: Text.Outline
        styleColor: ColorUtils.transparentize(Appearance.colors.colLayer0, 0.2)
    }

    // Always-visible marker when this image is the right-sidebar waifu.
    MaterialSymbol {
        visible: root.isWaifu
        anchors {
            top: parent.top
            left: parent.left
            margins: 6
        }
        text: "favorite"
        iconSize: Appearance.font.pixelSize.large
        color: Appearance.colors.colPrimary
        style: Text.Outline
        styleColor: ColorUtils.transparentize(Appearance.colors.colLayer0, 0.2)
    }

    // Hover is tracked with a HoverHandler (not the click MouseArea below): a
    // handler stays "hovered" even when the pointer is over the action buttons
    // that the veil reveals. Driving the veil from the MouseArea instead makes
    // it flicker, because each revealed button steals hover from the MouseArea,
    // hiding the veil again in an endless loop.
    HoverHandler {
        id: tileHover
    }

    MouseArea {
        id: mouseArea
        anchors.fill: parent
        acceptedButtons: Qt.LeftButton | Qt.RightButton
        cursorShape: root.gated ? Qt.ForbiddenCursor : Qt.PointingHandCursor
        onClicked: (mouse) => {
            if (mouse.button === Qt.RightButton) {
                root.toggleBookmark();
            } else if (!root.gated) {
                root.activate();
            }
        }
    }

    // Hover veil + action row.
    Rectangle {
        anchors.fill: parent
        visible: tileHover.hovered && !root.gated
        color: ColorUtils.transparentize("#000000", 0.55)

        Flow {
            anchors.centerIn: parent
            spacing: 2
            // Wrap when the tile is too narrow for one row (3–4 column layouts);
            // an unconstrained width would silently clip the outer buttons.
            width: Math.min(implicitWidth, parent.width - 8)

            component TileAction: RippleButton {
                id: action
                required property string symbol
                required property string tip
                signal triggered()

                implicitWidth: 34
                implicitHeight: 34
                buttonRadius: Appearance.rounding.full
                colBackground: "transparent"
                colBackgroundHover: ColorUtils.transparentize(Appearance.colors.colOnLayer1, 0.8)
                colRipple: ColorUtils.transparentize(Appearance.colors.colOnLayer1, 0.6)
                contentItem: MaterialSymbol {
                    horizontalAlignment: Text.AlignHCenter
                    verticalAlignment: Text.AlignVCenter
                    text: action.symbol
                    iconSize: Appearance.font.pixelSize.large
                    color: Appearance.colors.colOnLayer1
                }
                onClicked: action.triggered()
                StyledToolTip { text: action.tip }
            }

            TileAction {
                symbol: root.isWaifu ? "favorite" : "favorite_border"
                tip: root.isWaifu ? Translation.tr("Unset sidebar waifu") : Translation.tr("Set as sidebar waifu")
                onTriggered: root.setWaifu()
            }
            TileAction {
                symbol: root.bookmarked ? "bookmark_added" : "bookmark_add"
                tip: root.bookmarked ? Translation.tr("Remove bookmark") : Translation.tr("Bookmark")
                onTriggered: root.toggleBookmark()
            }
            TileAction {
                symbol: "download"
                tip: Translation.tr("Download")
                onTriggered: root.download()
            }
            TileAction {
                symbol: "open_in_new"
                tip: Translation.tr("Open image")
                onTriggered: root.openUrl(root.effectiveUrl)
            }
            TileAction {
                symbol: "link"
                tip: Translation.tr("Go to source")
                visible: (root.imageData?.source ?? "").length > 0
                onTriggered: root.openUrl(root.imageData.source)
            }
            TileAction {
                symbol: "content_copy"
                tip: Translation.tr("Copy image link")
                onTriggered: Quickshell.clipboardText = root.effectiveUrl
            }
        }
    }
}
