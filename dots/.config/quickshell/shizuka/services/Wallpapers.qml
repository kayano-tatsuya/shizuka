import qs.modules.common
import qs.modules.common.models
import qs.modules.common.functions
import QtQuick
import Qt.labs.folderlistmodel
import Quickshell
import Quickshell.Io
pragma Singleton
pragma ComponentBehavior: Bound

/**
 * Provides a list of wallpapers and an "apply" action that calls the existing
 * switchwall.sh script. Pretty much a limited file browsing service.
 */
Singleton {
    id: root

    property string thumbgenScriptPath: `${FileUtils.trimFileProtocol(Directories.scriptPath)}/thumbnails/thumbgen-venv.sh`
    property string generateThumbnailsMagickScriptPath: `${FileUtils.trimFileProtocol(Directories.scriptPath)}/thumbnails/generate-thumbnails-magick.sh`
    property string thumbCheckScriptPath: `${FileUtils.trimFileProtocol(Directories.scriptPath)}/thumbnails/check-thumbnails-venv.sh`
    function getCleanDirPath(path) {
        if (!path) return "";
        return FileUtils.trimFileProtocol(path.toString()).replace(/\/+$/, "");
    }

    property alias directory: folderModel.folder
    readonly property string effectiveDirectory: getCleanDirPath(folderModel.folder)
    property url defaultFolder: Qt.resolvedUrl(`${Directories.pictures}/Wallpapers`)
    property alias folderModel: folderModel // Expose for direct binding when needed
    property alias wallpaperModel: wallpaperModel
    property string sortMode: Config.options.wallpaperSelector?.sortMode || "custom"
    onSortModeChanged: debounceRebuildTimer.restart()
    property var orderMap: ({})
    property bool orderLoaded: false
    property string searchQuery: ""
    readonly property list<string> extensions: [ // TODO: add videos
        "jpg", "jpeg", "png", "webp", "avif", "bmp", "svg"
    ]
    property list<string> wallpapers: [] // List of absolute file paths (without file://)
    readonly property bool thumbnailGenerationRunning: thumbgenProc.running
    property real thumbnailGenerationProgress: 0
    property string previewPath: ""  // Set during arrow navigation; empty by default
    property string confirmedPath: ""  // Holds confirmed path until config catches up

    signal changed()
    signal thumbnailGenerated(directory: string)
    signal thumbnailGeneratedFile(filePath: string)

    function load () {} // For forcing initialization

    function startPreview(path) {
        if (!path || path.length === 0) return;
        root.previewPath = path;
    }

    function stopPreview() {
        root.previewPath = "";
    }

    // Executions
    Process {
        id: applyProc
    }
    
    function openFallbackPicker(darkMode = Appearance.m3colors.darkmode, startDir = "") {
        const args = [Directories.wallpaperSwitchScriptPath, "--mode", darkMode ? "dark" : "light"];
        if (startDir !== "") {
            args.push("--start-dir", startDir);
        }
        Quickshell.execDetached(args);
    }

    function apply(path, darkMode = Appearance.m3colors.darkmode) {
        if (!path || path.length === 0) return;
        root.confirmedPath = path;
        Quickshell.execDetached([Directories.wallpaperSwitchScriptPath, "--mode", darkMode ? "dark" : "light", "--image", path]);
        root.changed()
    }

    Process {
        id: selectProc
        property string filePath: ""
        property bool darkMode: Appearance.m3colors.darkmode
        property var onFileSelected: null
        function select(filePath, darkMode = Appearance.m3colors.darkmode, onFileSelected = null) {
            selectProc.filePath = filePath
            selectProc.darkMode = darkMode
            selectProc.onFileSelected = onFileSelected
            selectProc.exec(["test", "-d", FileUtils.trimFileProtocol(filePath)])
        }
        onExited: (exitCode, exitStatus) => {
            if (exitCode === 0) {
                setDirectory(selectProc.filePath);
                return;
            }
            if (selectProc.onFileSelected) {
                selectProc.onFileSelected(selectProc.filePath);
            } else {
                root.apply(selectProc.filePath, selectProc.darkMode);
            }
        }
    }

    function select(filePath, darkMode = Appearance.m3colors.darkmode, onFileSelected = null) {
        selectProc.select(filePath, darkMode, onFileSelected);
    }

    function randomFromCurrentFolder(darkMode = Appearance.m3colors.darkmode) {
        const count = wallpaperModel.count > 0 ? wallpaperModel.count : folderModel.count;
        if (count === 0) return;
        const randomIndex = Math.floor(Math.random() * count);
        const item = wallpaperModel.count > 0 ? wallpaperModel.get(randomIndex) : null;
        const filePath = item ? item.filePath : folderModel.get(randomIndex, "filePath");
        print("Randomly selected wallpaper:", filePath);
        if (filePath) root.select(filePath, darkMode);
    }

    function getRandomWallpaperPath(excludePath = "") {
        const count = wallpaperModel.count > 0 ? wallpaperModel.count : folderModel.count;
        if (count === 0) return "";
        const excludeClean = FileUtils.trimFileProtocol(excludePath);
        const candidates = [];
        for (let i = 0; i < count; i++) {
            const item = wallpaperModel.count > 0 ? wallpaperModel.get(i) : null;
            const path = item ? item.filePath : (folderModel.get(i, "filePath") || FileUtils.trimFileProtocol(folderModel.get(i, "fileURL")));
            if (path && path.length && FileUtils.trimFileProtocol(path) !== excludeClean) {
                candidates.push(path);
            }
        }
        if (candidates.length === 0) return "";
        return candidates[Math.floor(Math.random() * candidates.length)];
    }

    Process {
        id: validateDirProc
        property string nicePath: ""
        function setDirectoryIfValid(path) {
            validateDirProc.nicePath = FileUtils.trimFileProtocol(path).replace(/\/+$/, "")
            if (/^\/*$/.test(validateDirProc.nicePath)) validateDirProc.nicePath = "/";
            validateDirProc.exec([
                "bash", "-c",
                `if [ -d "${validateDirProc.nicePath}" ]; then echo dir; elif [ -f "${validateDirProc.nicePath}" ]; then echo file; else echo invalid; fi`
            ])
        }
        stdout: StdioCollector {
            onStreamFinished: {
                const result = text.trim()
                if (result === "dir") {
                    root.directory = Qt.resolvedUrl(validateDirProc.nicePath)
                } else if (result === "file") {
                    root.directory = Qt.resolvedUrl(FileUtils.parentDirectory(validateDirProc.nicePath))
                } else {
                    // The assignment used to happen above, before this check, which
                    // made the "ignore" branch a lie: a path that doesn't exist was
                    // still assigned, the model went empty, and the picker showed a
                    // blank panel with no explanation. Refuse to navigate instead.
                    console.log("[Wallpapers] setDirectory: not a path, staying in", root.effectiveDirectory)
                }
            }
        }
    }
    function setDirectory(path) {
        validateDirProc.setDirectoryIfValid(path)
    }
    function navigateUp() {
        folderModel.navigateUp()
    }
    function navigateBack() {
        folderModel.navigateBack()
    }
    function navigateForward() {
        folderModel.navigateForward()
    }

    // Folder model
    FolderListModelWithHistory {
        id: folderModel
        folder: Qt.resolvedUrl(root.defaultFolder)
        caseSensitive: false
        nameFilters: root.extensions.map(ext => `*${searchQuery.split(" ").filter(s => s.length > 0).map(s => `*${s}*`)}*.${ext}`)
        showDirs: true
        showDotAndDotDot: false
        showOnlyReadable: true
        sortField: FolderListModel.Time
        sortReversed: false
        onCountChanged: debounceRebuildTimer.restart()
        onStatusChanged: {
            if (status === FolderListModel.Ready) debounceRebuildTimer.restart();
        }
    }

    onEffectiveDirectoryChanged: debounceRebuildTimer.restart()
    onSearchQueryChanged: debounceRebuildTimer.restart()

    ListModel {
        id: wallpaperModel
    }

    FileView {
        id: orderFileView
        path: `${Directories.shellConfig}/wallpaper_order.json`
        watchChanges: false
        onLoaded: {
            try {
                const txt = orderFileView.text();
                if (txt && txt.trim().length > 0) {
                    root.orderMap = JSON.parse(txt);
                } else {
                    root.orderMap = {};
                }
            } catch (e) {
                console.log("[Wallpapers] Error parsing wallpaper_order.json:", e);
                root.orderMap = {};
            }
            root.orderLoaded = true;
            debounceRebuildTimer.restart();
        }
        onLoadFailed: (error) => {
            root.orderMap = {};
            root.orderLoaded = true;
            debounceRebuildTimer.restart();
        }
    }

    Connections {
        target: Config.options.wallpaperSelector ?? null
        function onSortModeChanged() {
            if (Config.options.wallpaperSelector?.sortMode && root.sortMode !== Config.options.wallpaperSelector.sortMode) {
                root.sortMode = Config.options.wallpaperSelector.sortMode;
                debounceRebuildTimer.restart();
            }
        }
    }

    Connections {
        target: Config
        function onReadyChanged() {
            if (Config.ready) {
                if (Config.options.wallpaperSelector?.sortMode) {
                    root.sortMode = Config.options.wallpaperSelector.sortMode;
                }
                debounceRebuildTimer.restart();
            }
        }
    }

    function saveCustomOrder() {
        const jsonStr = JSON.stringify(root.orderMap, null, 2);
        if (orderFileView) {
            try {
                orderFileView.setText(jsonStr);
            } catch (e) {
                console.log("[Wallpapers] Failed to save wallpaper_order.json:", e);
            }
        }
        const filePath = `${Directories.shellConfig}/wallpaper_order.json`;
        Quickshell.execDetached(["bash", "-c", `mkdir -p '${Directories.shellConfig}' && cat << 'EOF' > '${filePath}.tmp' && mv '${filePath}.tmp' '${filePath}'\n${jsonStr}\nEOF`]);
    }

    function moveWallpaper(fromIndex, toIndex) {
        if (fromIndex < 0 || toIndex < 0 || fromIndex >= wallpaperModel.count || toIndex >= wallpaperModel.count || fromIndex === toIndex)
            return;

        wallpaperModel.move(fromIndex, toIndex, 1);
        root.sortMode = "custom";
        if (Config.options.wallpaperSelector) {
            Config.options.wallpaperSelector.sortMode = "custom";
        }
        Config.setNestedValue("wallpaperSelector.sortMode", "custom");

        const list = [];
        const paths = [];
        for (let i = 0; i < wallpaperModel.count; i++) {
            const it = wallpaperModel.get(i);
            list.push(it.fileName);
            if (it.filePath) paths.push(it.filePath);
        }
        const cleanDir = getCleanDirPath(folderModel.folder);
        root.orderMap[cleanDir] = list;
        root.wallpapers = paths;
        root.saveCustomOrder();
    }

    function moveToTop(index) {
        moveWallpaper(index, 0);
    }

    function moveToBottom(index) {
        moveWallpaper(index, wallpaperModel.count - 1);
    }

    function setSortMode(mode) {
        root.sortMode = mode;
        if (Config.options.wallpaperSelector) {
            Config.options.wallpaperSelector.sortMode = mode;
        }
        Config.setNestedValue("wallpaperSelector.sortMode", mode);
        rebuildWallpaperModel();
    }

    Timer {
        id: debounceRebuildTimer
        interval: 20
        repeat: false
        onTriggered: root.rebuildWallpaperModel()
    }

    function sortItems(items, mode, customList) {
        if (mode === "custom") {
            if (!customList || customList.length === 0) {
                return items.slice().sort((a, b) => {
                    if (a.fileIsDir !== b.fileIsDir) return a.fileIsDir ? -1 : 1;
                    return new Date(b.fileModified) - new Date(a.fileModified);
                });
            }
            const orderLookup = {};
            for (let i = 0; i < customList.length; i++) {
                orderLookup[customList[i]] = i;
            }
            const dirs = [];
            const orderedFiles = [];
            const remainingFiles = [];
            for (let i = 0; i < items.length; i++) {
                const it = items[i];
                if (it.fileIsDir) {
                    dirs.push(it);
                } else if (typeof orderLookup[it.fileName] !== "undefined") {
                    orderedFiles.push(it);
                } else {
                    remainingFiles.push(it);
                }
            }
            dirs.sort((a, b) => a.fileName.localeCompare(b.fileName, undefined, { numeric: true, sensitivity: "base" }));
            orderedFiles.sort((a, b) => orderLookup[a.fileName] - orderLookup[b.fileName]);
            remainingFiles.sort((a, b) => new Date(b.fileModified) - new Date(a.fileModified));
            return dirs.concat(orderedFiles, remainingFiles);
        } else if (mode === "name") {
            return items.slice().sort((a, b) => {
                if (a.fileIsDir !== b.fileIsDir) return a.fileIsDir ? -1 : 1;
                return a.fileName.localeCompare(b.fileName, undefined, { numeric: true, sensitivity: "base" });
            });
        } else if (mode === "name_rev") {
            return items.slice().sort((a, b) => {
                if (a.fileIsDir !== b.fileIsDir) return a.fileIsDir ? -1 : 1;
                return b.fileName.localeCompare(a.fileName, undefined, { numeric: true, sensitivity: "base" });
            });
        } else if (mode === "time") {
            return items.slice().sort((a, b) => {
                if (a.fileIsDir !== b.fileIsDir) return a.fileIsDir ? -1 : 1;
                return new Date(b.fileModified) - new Date(a.fileModified);
            });
        } else if (mode === "time_rev") {
            return items.slice().sort((a, b) => {
                if (a.fileIsDir !== b.fileIsDir) return a.fileIsDir ? -1 : 1;
                return new Date(a.fileModified) - new Date(b.fileModified);
            });
        } else if (mode === "size") {
            return items.slice().sort((a, b) => {
                if (a.fileIsDir !== b.fileIsDir) return a.fileIsDir ? -1 : 1;
                return (b.fileSize || 0) - (a.fileSize || 0);
            });
        } else if (mode === "size_rev") {
            return items.slice().sort((a, b) => {
                if (a.fileIsDir !== b.fileIsDir) return a.fileIsDir ? -1 : 1;
                return (a.fileSize || 0) - (b.fileSize || 0);
            });
        }
        return items;
    }

    function rebuildWallpaperModel() {
        const count = folderModel.count;
        if (count === 0) {
            wallpaperModel.clear();
            root.wallpapers = [];
            return;
        }

        const items = [];
        for (let i = 0; i < count; i++) {
            const fn = folderModel.get(i, "fileName") || "";
            const fp = folderModel.get(i, "filePath") || "";
            const fu = (fp && fp.length) ? ("file://" + fp) : (folderModel.get(i, "fileUrl") || "");
            const isDir = Boolean(folderModel.get(i, "fileIsDir"));
            const sz = folderModel.get(i, "fileSize") || 0;
            const mod = folderModel.get(i, "fileModified") ? folderModel.get(i, "fileModified").toString() : "";
            items.push({
                fileName: fn,
                filePath: fp,
                fileUrl: fu,
                fileURL: fu,
                fileIsDir: isDir,
                fileSize: sz,
                fileModified: mod
            });
        }

        const cleanDir = getCleanDirPath(folderModel.folder);
        const savedOrder = root.orderMap[cleanDir] || root.orderMap[cleanDir + "/"] || [];
        const effectiveMode = (root.sortMode === "custom" || (!root.sortMode && savedOrder.length > 0)) ? "custom" : root.sortMode;
        const sorted = sortItems(items, effectiveMode, savedOrder);

        wallpaperModel.clear();
        const paths = [];
        for (let i = 0; i < sorted.length; i++) {
            wallpaperModel.append(sorted[i]);
            if (sorted[i].filePath && sorted[i].filePath.length) {
                paths.push(sorted[i].filePath);
            }
        }
        root.wallpapers = paths;
    }

    // Thumbnail generation
    //
    // Previews are NOT loaded from the image; they are read from the Freedesktop
    // thumbnail cache (~/.cache/thumbnails/<size>/<md5>.png). A cache miss means
    // a blank tile. This section decides when to (re)populate that cache.
    //
    // The primary generator is thumbgen-venv.sh (GnomeDesktop, spec-correct,
    // supports -r/-i/--max_depth and reports machine-readable progress).
    // generate-thumbnails-magick.sh is the "||" fallback and is kept
    // spec-compatible so switching between them does not invalidate the cache.
    //
    // We only recurse when browsing under ~/Pictures. The picker's "Home" tab
    // points at ~ (325k files on this machine), so an unconditional recursive
    // pass would be ruinous. Depth is bounded relative to the directory being
    // viewed, not from /home.

    // Cheap "does this tree still need work?" probe. Runs check-thumbnails.py,
    // which reuses GnomeDesktop's own lookup() so the check can never drift
    // from the writer. Exit 0 => work needed, 1 => nothing to do.
    property bool thumbCheckBusy: false
    Process {
        id: thumbCheckProc
        property string size: "x-large"
        stdout: StdioCollector {
            onStreamFinished: {
                const n = parseInt(text.trim());
                if (n > 0)
                    root.generateThumbnail(thumbCheckProc.size);
            }
        }
        onExited: {
            root.thumbCheckBusy = false;
        }
    }

    function maxDepthFor(dir) {
        const clean = getCleanDirPath(dir);
        const pics = getCleanDirPath(Directories.pictures);
        // Recurse (bounded) only inside the pictures root.
        return (clean === pics || clean.startsWith(pics + "/")) ? 5 : 0;
    }

    // Called on directory change / picker open. Does nothing if a probe or a
    // generation is already running, so rapid navigation does not thrash.
    function ensureThumbnails(size) {
        if (thumbCheckBusy || thumbgenProc.running) return;
        const dir = root.effectiveDirectory;
        if (!dir) return;
        thumbCheckProc.size = size;
        thumbCheckProc.command = [
            "bash", thumbCheckScriptPath,
            dir, size, String(maxDepthFor(dir)),
        ];
        thumbCheckBusy = true;
        thumbCheckProc.running = true;
    }

    // Regenerate for the current directory. Both the primary and the fallback
    // generator already skip fresh thumbnails, so calling this when everything
    // is cached is a cheap no-op -- that is what lets the toolbar button force
    // a run without a separate code path.
    function generateThumbnail(size: string) {
        if (!["normal", "large", "x-large", "xx-large"].includes(size)) throw new Error("Invalid thumbnail size");
        if (thumbgenProc.running) {
            // Don't kill an in-flight run for the same directory; that used to
            // thrash on rapid navigation and never finish anything.
            if (thumbgenProc.directory === root.effectiveDirectory) return;
            thumbgenProc.running = false;
        }
        const dir = FileUtils.trimFileProtocol(root.effectiveDirectory);
        const depth = maxDepthFor(dir);
        const recursive = depth > 0 ? " -r -i --max_depth " + depth : "";
        // The `||` fallback needs a shell, so this has to be a command *string*
        // rather than an argv array -- which means the path must be quoted by
        // hand. It was not, and the picker's own default tree has a directory
        // with a space in it ("SAVED (NO OVERRIDES)"), so bash word-split it
        // and then parsed "(NO OVERRIDES)" as a subshell. The run failed
        // silently: exit status was still 0 because thumbgen.py catches its own
        // exceptions, so `||` never fired either and no fallback happened.
        const q = `"${dir.replace(/"/g, '\\"')}"`;
        thumbgenProc.directory = dir;
        thumbgenProc.command = [
            "bash", "-c",
            `${thumbgenScriptPath} --size ${size}${recursive} --machine_progress -d ${q} || ${generateThumbnailsMagickScriptPath} --size ${size}${recursive ? " --recursive --max-depth " + depth : ""} -d ${q}`,
        ]
        root.thumbnailGenerationProgress = 0
        thumbgenProc.running = true
    }
    Process {
        id: thumbgenProc
        property string directory
        stdout: SplitParser {
            onRead: data => {
                // print("thumb gen proc:", data)
                let match = data.match(/PROGRESS (\d+)\/(\d+)/)
                if (match) {
                    const completed = parseInt(match[1])
                    const total = parseInt(match[2])
                    root.thumbnailGenerationProgress = completed / total
                }
                match = data.match(/FILE (.+)/)
                if (match) {
                    const filePath = match[1]
                    root.thumbnailGeneratedFile(filePath)
                }
            }
        }
        onExited: (exitCode, exitStatus) => {
            // print("[Wallpapers] Thumbnail generation completed with exit code", exitCode)
            root.thumbnailGenerated(thumbgenProc.directory)
        }
    }

    IpcHandler {
        target: "wallpapers"

        function apply(path: string): void {
            root.apply(path);
        }

        function setSortMode(mode: string): void {
            root.setSortMode(mode);
        }

        function moveWallpaper(fromIndex: int, toIndex: int): void {
            root.moveWallpaper(fromIndex, toIndex);
        }

        function setSddmWallpaper(path: string): void {
            root.applySddmWallpaper(path);
        }
    }

    // ---------------------------------------------------------- SDDM / login
    // The login greeter (SDDM / plasmalogin) paints its background from the SDDM
    // theme.conf; we rewrite that one line via pkexec. Guarded on the conf
    // existing, and the path is configurable since DM/theme layouts vary.
    property string sddmThemeConf: Config.options.background.sddmThemeConf || "/usr/share/sddm/themes/where_is_my_sddm_theme/theme.conf"
    property bool sddmThemeAvailable: false

    function refreshSddmAvailability() {
        if (!sddmCheckProc.running)
            sddmCheckProc.running = true;
    }

    property Process sddmCheckProc: Process {
        command: ["bash", "-c", `test -f '${root.sddmThemeConf}'`]
        onExited: (code, status) => {
            root.sddmThemeAvailable = (code === 0);
        }
    }

    function applySddmWallpaper(path) {
        if (!path || path.length === 0)
            return;
        Config.options.background.sddmWall = path;
        // sed replacement: escape backslash, '&' (whole-match), and the '|'
        // delimiter. A stray '&' would otherwise corrupt the line.
        const esc = path.replace(/[\\&|]/g, c => "\\" + c);
        Quickshell.execDetached(["pkexec", "bash", "-c",
            `conf='${root.sddmThemeConf}'; if [ -f "$conf" ]; then sed -i 's|^background=.*|background=${esc}|' "$conf"; fi`]);
    }

    Component.onCompleted: root.refreshSddmAvailability()
}