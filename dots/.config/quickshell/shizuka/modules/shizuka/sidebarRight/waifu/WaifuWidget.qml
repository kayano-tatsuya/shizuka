import qs.services
import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets
import Qt5Compat.GraphicalEffects
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io

/**
 * Random waifu banner for the top of the right sidebar. It fills the slot the
 * wallpaper preview used to occupy; the image itself comes from the `Waifu`
 * service, so this file only paints and reacts.
 *
 * Hovering the image reveals the actions: refresh, download, set as wallpaper
 * and open source. The hover state is tracked with a HoverHandler (not a
 * MouseArea): a handler stays "hovered" even when the pointer is over the
 * buttons the veil reveals, which is what keeps the overlay from flickering.
 */
Item {
    id: root

    property real radius: Appearance.rounding.normal
    readonly property bool hoverActions: Config.options?.sidebar?.waifu?.hoverActions ?? true

    readonly property var image: Waifu.current
    // Prefer the (smaller, faster) sample/preview URLs: the full-res file_url
    // (especially yande.re's) is multi-MB and QML's async Image loader can
    // stall/fail on it, leaving the banner blank ("infinitely loading").
    readonly property string imageUrl: root.image?.sample_url ?? root.image?.preview_url ?? root.image?.file_url ?? ""
    readonly property string sourceUrl: root.image?.source ?? ""

    // ---- Sizing ----
    // The banner is as tall as the image's aspect ratio needs, so portrait art
    // is not squashed into a fixed strip. The bounds stop an extreme ratio from
    // swallowing the sidebar; outside them the image crops instead of growing.
    property real minBannerHeight: 120
    property real maxBannerHeight: 320

    // Prefer the provider's reported dimensions (known immediately, so the
    // height does not jump once the file finishes loading); fall back to the
    // intrinsic size QML reads off the file, which covers providers that report
    // nothing at all.
    readonly property real imageAspect: {
        const w = root.image?.width ?? 0;
        const h = root.image?.height ?? 0;
        if (w > 0 && h > 0) return h / w;
        if (preview.implicitWidth > 0 && preview.implicitHeight > 0)
            return preview.implicitHeight / preview.implicitWidth;
        return 0.62; // portrait-ish guess until the image reports its size
    }
    readonly property real desiredHeight: Math.max(root.minBannerHeight,
        Math.min(root.maxBannerHeight, Math.max(1, root.width) * root.imageAspect))
    // Read by the banner container (see SidebarRightContent) to size itself.
    implicitHeight: Math.round(root.desiredHeight)

    // Asks the service to show the pinned waifu or fetch a first one. The
    // service owns the "is there anything to show yet" decision (and waits for
    // Persistent to load), so the widget only nudges it on becoming visible.
    function ensureImage() {
        if (root.visible)
            Waifu.ensureLoaded();
    }
    Component.onCompleted: root.ensureImage()
    onVisibleChanged: root.ensureImage()

    // ---- Placeholder while loading / with nothing to show ----
    Rectangle {
        anchors.fill: parent
        radius: root.radius
        color: Appearance.colors.colLayer2
    }
    MaterialSymbol {
        anchors.centerIn: parent
        visible: root.imageUrl.length === 0
        text: Waifu.loading ? "hourglass_top" : "broken_image"
        iconSize: 28
        color: Appearance.colors.colOnLayer2
        opacity: 0.5
    }

    // ---- Image ----
    StyledImage {
        id: preview
        anchors.fill: parent
        fillMode: Image.PreserveAspectCrop
        onStatusChanged: console.log("[WaifuWidget] preview status:", status, "source:", source, "implicit:", implicitWidth, implicitHeight)
        // Only the width is pinned; Qt derives the height from the aspect ratio
        // (pinning both would make `imageAspect` depend on itself). Alignment
        // only matters when an extreme ratio is clamped above/below.
        verticalAlignment: Image.AlignTop
        source: root.imageUrl
        sourceSize.width: Math.max(1, root.width) * 2
        layer.enabled: true
        layer.effect: OpacityMask {
            maskSource: Rectangle {
                width: root.width
                height: root.height
                radius: root.radius
            }
        }
    }

    HoverHandler {
        id: hover
    }

    // ---- Hover veil + actions ----
    Rectangle {
        anchors.fill: parent
        radius: root.radius
        visible: hover.hovered && root.hoverActions && root.imageUrl.length > 0
        color: ColorUtils.transparentize("#000000", 0.55)

        RowLayout {
            anchors.centerIn: parent
            spacing: 2

            component WaifuAction: RippleButton {
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

            WaifuAction {
                symbol: "refresh"
                tip: Translation.tr("New waifu")
                onTriggered: Waifu.refresh()
            }
            WaifuAction {
                symbol: "download"
                tip: Translation.tr("Download")
                onTriggered: root.save(false)
            }
            WaifuAction {
                symbol: "wallpaper"
                tip: Translation.tr("Set as wallpaper")
                onTriggered: root.save(true)
            }
            WaifuAction {
                symbol: "open_in_new"
                tip: Translation.tr("Open source")
                visible: root.sourceUrl.length > 0
                onTriggered: root.openUrl(root.sourceUrl)
            }
        }
    }

    function openUrl(url) {
        if (!url || url.length === 0) return;
        Qt.openUrlExternally(url);
    }

    function fileName() {
        const url = root.imageUrl;
        const base = decodeURIComponent(url.substring(url.lastIndexOf("/") + 1));
        return base.length > 0 ? base : ("waifu_" + Date.now());
    }

    // One curl per action. Download just notifies; set-as-wallpaper applies the
    // freshly saved file through the shell's usual wallpaper switch script.
    Process {
        id: fetchProc
        property string target: ""
        property bool applyAfter: false
        onExited: (code) => {
            if (code !== 0) return;
            if (fetchProc.applyAfter) {
                Wallpapers.apply(fetchProc.target);
            } else {
                Quickshell.execDetached(["notify-send", Translation.tr("Download complete"), fetchProc.target, "-a", "Shell"]);
            }
        }
    }

    function save(applyAfter) {
        if (root.imageUrl.length === 0) return;
        const target = `${Directories.waifuDownloads}/${root.fileName()}`;
        fetchProc.target = target;
        fetchProc.applyAfter = applyAfter;
        const ua = Config.options?.networking?.userAgent ?? "";
        const uaArg = ua ? ` -H 'User-Agent: ${StringUtils.shellSingleQuoteEscape(ua)}'` : "";
        fetchProc.command = ["bash", "-c",
            `mkdir -p '${StringUtils.shellSingleQuoteEscape(Directories.waifuDownloads)}' && curl -fsSL '${StringUtils.shellSingleQuoteEscape(root.imageUrl)}'${uaArg} -o '${StringUtils.shellSingleQuoteEscape(target)}'`];
        fetchProc.running = true;
    }
}
