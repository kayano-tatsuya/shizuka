pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import qs.modules.common
import qs.modules.common.functions

/**
 * Booru pin sync — syncs booru pins to the fastfetch cache directory
 * (~/.config/fastfetch/cache) as rounded WebP images, so fastfetch.sh's
 * random-logo pick can show a booru image in the terminal.
 *
 * Ported from ArchEclipse's FastfetchPins, adapted to shizuka's
 * Persistent.states.booru.pins and Config.options.networking.userAgent.
 */
Singleton {
    id: root

    property string cacheDir: Quickshell.env("HOME") + "/.config/fastfetch/cache"
    readonly property string booruBase: Quickshell.env("HOME") + "/.cache/quickshell/booru"
    readonly property string generatedPrefix: "booru-pin-"
    readonly property int cornerRadiusPercent: 5
    readonly property int debounceMs: 250

    property bool _started: false
    property bool _syncInProgress: false
    property bool _resyncQueued: false
    property string _lastPinsSignature: ""
    property var _currentExpectedPaths: []
    property var _pendingExpected: []

    property Timer _debounceTimer: Timer {
        interval: root.debounceMs
        repeat: false
        onTriggered: root.runSync()
    }

    // ---- helpers ---------------------------------------------------------
    function shQuote(s) {
        return "'" + String(s).replace(/'/g, "'\\''") + "'"
    }

    function userAgent() {
        const ua = Config.options?.networking?.userAgent ?? ""
        return ua !== "" ? ua : "Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"
    }

    function sanitizeSegment(value) {
        return String(value).replace(/[^a-zA-Z0-9_-]/g, "_")
    }

    function getPinKey(pin) {
        if (typeof pin.id !== "number") return null
        const apiValue = (pin.api || {}).value || (pin.provider) || ""
        if (typeof apiValue !== "string" || !apiValue) return null
        return pin.id + ":" + apiValue
    }

    function getPinsSignature(pins) {
        const parts = []
        for (const pin of (pins || [])) {
            const key = getPinKey(pin)
            if (!key) continue
            parts.push(key + ":" + (pin.extension || ""))
        }
        parts.sort()
        return parts.join("|")
    }

    function localImagePath(pin) {
        const key = getPinKey(pin)
        if (!key) return ""
        const [id, apiValue] = key.split(":")
        if (!id || !apiValue) return ""
        const ext = pin.extension || "jpg"
        return root.booruBase + "/" + apiValue + "/images/" + id + "." + ext
    }

    function getCachePath(pin) {
        const key = getPinKey(pin)
        if (!key) return null
        const [id, apiValue] = key.split(":")
        if (!id || !apiValue) return null
        return root.cacheDir + "/" + root.generatedPrefix + root.sanitizeSegment(apiValue) + "-" + id + ".webp"
    }

    function getSourcePath(pin) {
        return root.localImagePath(pin)
    }

    // ---- magick conversion ----------------------------------------------
    property Process _magickProc: Process {
        property string currentSource: ""
        property string currentCache: ""
        property int pendingCount: 0
        property var expectedPaths: []
        onExited: (code, status) => {
            if (code !== 0)
                console.warn("[FastfetchPins] magick failed for " + currentSource + " exit=" + code)
            processNext()
        }
        function processNext() {
            if (pendingCount <= 0) {
                root._cleanupStale(root._currentExpectedPaths)
                root._pokeZsh()
                root._syncInProgress = false
                if (root._resyncQueued) {
                    root._resyncQueued = false
                    Qt.callLater(root.runSync)
                }
                return
            }
            pendingCount--
            const item = expectedPaths[pendingCount]
            currentSource = item.src
            currentCache = item.dst
            if (!currentSource || !currentCache) { processNext(); return }
            root._checkFileExists(currentCache, (cacheExists) => {
                if (cacheExists) { processNext(); return }
                const radius = "%[fx:min(w,h)*" + (root.cornerRadiusPercent / 100) + "]"
                command = [
                    "magick", currentSource,
                    "-alpha", "set",
                    "(", "+clone",
                        "-alpha", "transparent",
                        "-background", "none",
                        "-fill", "white",
                        "-draw", "roundrectangle 0,0,%[fx:w-1],%[fx:h-1]," + radius + "," + radius,
                    ")",
                    "-compose", "Dst_In", "-composite",
                    "-strip",
                    "-quality", "82",
                    "-define", "webp:method=6",
                    "-define", "webp:alpha-quality=90",
                    "-background", "none",
                    currentCache
                ]
                running = true
            })
        }
    }

    // ---- self-heal missing source ---------------------------------------
    function _ensureSource(item, cb) {
        const done = (ok) => { if (cb) cb(ok) }
        if (!item || !item.src) { done(false); return }
        if (!item.url) {
            console.warn("[FastfetchPins] No url to fetch missing source: " + item.src)
            done(false)
            return
        }
        const dir = item.src.substring(0, item.src.lastIndexOf("/"))
        let fetchCmd
        if (/^https?:\/\//.test(item.url)) {
            const referer = item.referer ? ` -H ${root.shQuote("Referer: " + item.referer)}` : ""
            fetchCmd = `mkdir -p ${JSON.stringify(dir)} && curl -sSfL -H ${root.shQuote("User-Agent: " + root.userAgent())}${referer} -o ${JSON.stringify(item.src)} ${JSON.stringify(item.url)}`
        } else {
            fetchCmd = `mkdir -p ${JSON.stringify(dir)} && cp -- ${JSON.stringify(item.url)} ${JSON.stringify(item.src)}`
        }
        _dlProc.callback = done
        _dlProc.expectSrc = item.src
        _dlProc.command = ["bash", "-c", fetchCmd]
        _dlProc.running = true
    }

    property Process _dlProc: Process {
        property var callback: null
        property string expectSrc: ""
        onExited: (code) => {
            const cb = _dlProc.callback
            _dlProc.callback = null
            if (code !== 0) {
                console.warn("[FastfetchPins] Failed to fetch missing source: " + _dlProc.expectSrc)
                if (cb) cb(false)
                return
            }
            root._checkFileExists(_dlProc.expectSrc, (ok) => { if (cb) cb(ok) })
        }
    }

    property Process _existsProc: Process {
        property string checkPath: ""
        property var callback: null
        onExited: (code) => {
            if (root._existsProc.callback) root._existsProc.callback(code === 0)
        }
    }

    function _checkFileExists(path, cb) {
        _existsProc.checkPath = path
        _existsProc.callback = cb
        _existsProc.command = ["test", "-f", path]
        _existsProc.running = true
    }

    // ---- sync orchestration ---------------------------------------------
    function syncPinsToFastfetchCache() {
        const pins = (Persistent.states.booru.pins) || []
        console.log("[FastfetchPins] Sync requested for " + pins.length + " pins")

        const expected = []
        for (const pin of pins) {
            const src = getSourcePath(pin)
            const dst = getCachePath(pin)
            const key = getPinKey(pin)
            if (src && dst && key) {
                expected.push({ src: src, dst: dst, key: key, api: (pin.api || {}).value || (pin.provider) || "", id: pin.id, url: pin.file_url || pin.sample_url || "", referer: (pin.imageReferer) || ((pin.api || {}).url) || "" })
            }
        }

        root._currentExpectedPaths = expected
        root._pendingExpected = expected
        _mkdirProc.command = ["mkdir", "-p", cacheDir]
        _mkdirProc.running = true
    }

    property Process _mkdirProc: Process {
        onExited: (code) => {
            if (code === 0) {
                _magickProc.expectedPaths = root._pendingExpected
                _magickProc.pendingCount = root._pendingExpected.length
                _magickProc.processNext()
            } else {
                console.warn("[FastfetchPins] Failed to create cache dir: " + cacheDir)
                root._syncInProgress = false
            }
        }
    }

    function runSync() {
        if (root._syncInProgress) {
            root._resyncQueued = true
            return
        }
        root._syncInProgress = true
        syncPinsToFastfetchCache()
    }

    function scheduleSync() {
        _debounceTimer.restart()
    }

    // ---- cleanup stale --------------------------------------------------
    function _cleanupStale(expectedPaths) {
        _cleanupProc.expectedSet = expectedPaths
        _cleanupProc.cacheDirectory = cacheDir
        _cleanupProc.command = ["ls", cacheDir]
        _cleanupProc.running = true
    }

    property Process _cleanupProc: Process {
        property var expectedSet: []
        property string cacheDirectory: ""
        stdout: StdioCollector {
            onStreamFinished: {
                const lines = text.trim().split("\n").filter(l => l.length > 0)
                for (const name of lines) {
                    if (!name.startsWith(root.generatedPrefix) || !name.endsWith(".webp")) continue
                    const nameNoExt = name.replace(/\.webp$/, "")
                    let found = false
                    for (const ep of _cleanupProc.expectedSet) {
                        const epName = root.generatedPrefix + root.sanitizeSegment(ep.api) + "-" + ep.id + ".webp"
                        if (name === epName) { found = true; break }
                    }
                    if (!found) {
                        root._removeFile(root.cacheDir + "/" + name)
                    }
                }
            }
        }
        onExited: {}
    }

    property Process _removeProc: Process {
        property string targetPath: ""
        onExited: (code) => {
            if (code !== 0)
                console.warn("[FastfetchPins] Failed to remove stale: " + targetPath)
        }
    }

    function _removeFile(path) {
        _removeProc.targetPath = path
        _removeProc.command = ["rm", "-f", path]
        _removeProc.running = true
    }

    // ---- poke zsh ------------------------------------------------------
    property Process _pokeProc: Process {
        command: ["bash", "-c", "pkill -SIGUSR1 zsh || true"]
        onExited: {}
    }

    function _pokeZsh() {
        _pokeProc.running = true
    }

    // ---- start / watch -------------------------------------------------
    function start() {
        if (root._started) return
        root._started = true
        const pins = (Persistent.states.booru.pins) || []
        root._lastPinsSignature = root.getPinsSignature(pins)
        root.scheduleSync()

        // Watch booru pins changes via a timer poll (Persistent may not emit a signal).
        // We poll every 2s for signature changes.
        _watchTimer.start()
    }

    property Timer _watchTimer: Timer {
        interval: 2000
        repeat: true
        running: false
        onTriggered: {
            const pins = (Persistent.states.booru.pins) || []
            const sig = root.getPinsSignature(pins)
            if (sig === root._lastPinsSignature) return
            root._lastPinsSignature = sig
            root.scheduleSync()
        }
    }

    Component.onCompleted: start()
}
