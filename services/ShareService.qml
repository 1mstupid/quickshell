pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

// Outgoing file shares through localsend-cli. Files queue here and go in one send to
// the phone's IP. The CLI can't find devices on this network, so the IP is fixed in
// config.toml's [settings] table, e.g. shareDevice = "100.117.26.7" (a Tailscale address). A file
// dragged onto the bar pill or the share panel queues it and opens the panel.
Singleton {
    id: root

    // the destination; empty until config.toml names one
    readonly property string selectedDevice: {
        const d = Config.data.settings?.shareDevice
        return typeof d === "string" ? d.trim() : ""
    }

    // paths waiting to be sent, in the order they were added
    property var queuedFiles: []

    // the tray: favourite files kept to hand. They are apart from the queue and are never
    // sent with it. Kept in ~/.local/state/lumin/tray, one path a line, so they survive a restart.
    property var favorites: []
    FileView {
        id: favFile
        path: Quickshell.env("HOME") + "/.local/state/lumin/tray"
        atomicWrites: true
        onLoaded: {
            root.favorites = text().split("\n").filter(p => p !== "")
            root.statFavorites()
        }
        onLoadFailed: root.favorites = []
    }

    // what each favourite is, by path, from one stat over them: { dir, size, mtime }; and
    // which are gone
    property var info: ({})
    property var missing: ({})
    function statFavorites() {
        statFavProc.running = false
        if (favorites.length === 0) {
            info = ({})
            missing = ({})
            return
        }
        statFavProc.command = ["timeout", "3", "stat", "-c", "%F\t%s\t%Y\t%n", "--"].concat(favorites)
        statFavProc.running = true
    }
    Process {
        id: statFavProc
        stdout: StdioCollector {
            onStreamFinished: {
                // type, size, mtime in seconds, then the path, which may hold tabs
                var found = {};
                for (const line of text.split("\n")) {
                    const a = line.indexOf("\t");
                    const b = a < 0 ? -1 : line.indexOf("\t", a + 1);
                    const c = b < 0 ? -1 : line.indexOf("\t", b + 1);
                    if (c < 0)
                        continue;
                    found[line.slice(c + 1)] = {
                        dir: line.slice(0, a) === "directory",
                        size: parseInt(line.slice(a + 1, b)),
                        mtime: parseInt(line.slice(b + 1, c))
                    };
                }
                var gone = {};
                for (const p of root.favorites) {
                    if (!found[p])
                        gone[p] = true;
                }
                root.info = found;
                root.missing = gone;
            }
        }
    }
    property int totalFileCount: 0
    property real totalSize: 0

    property bool expanding: false
    property bool sending: false
    // why the last send failed; empty after a success or before any send
    property string lastError: ""

    // the share panel is open; a drag that leaves without a drop closes it after a short wait
    property bool panelOpen: false
    // a drop happened during this drag, so the exit that follows it must not close the panel
    property bool dropped: false

    function open() {
        closeTimer.stop()
        dropped = false
        panelOpen = true
    }

    function scheduleClose() {
        if (panelOpen && !dropped)
            closeTimer.restart()
    }

    function cancelClose() {
        closeTimer.stop()
        dropped = false
    }

    function close() {
        closeTimer.stop()
        panelOpen = false
    }

    Timer {
        id: closeTimer
        interval: 300
        onTriggered: root.close()
    }

    function formatSize(bytes) {
        if (bytes <= 0) return "0 B"
        const k = 1024
        const sizes = ["B", "KB", "MB", "GB", "TB"]
        const i = Math.floor(Math.log(bytes) / Math.log(k))
        return parseFloat((bytes / Math.pow(k, i)).toFixed(1)) + " " + sizes[i]
    }

    function notify(summary, body, urgency) {
        notifyProc.command = [
            "notify-send",
            "-a", "LocalSend",
            "-u", urgency || "normal",
            summary,
            body
        ]
        notifyProc.running = true
    }

    // a path already in the queue is not added twice
    function addFile(path) {
        if (path === "" || queuedFiles.indexOf(path) >= 0)
            return
        queuedFiles = queuedFiles.concat([path])
    }

    // drop URLs are file:// URIs; anything else is ignored
    function pathsOf(urls) {
        const out = []
        for (let i = 0; i < urls.length; i++) {
            const s = String(urls[i])
            if (s.indexOf("file://") !== 0)
                continue
            try {
                out.push(decodeURIComponent(s.slice(7)))
            } catch (e) {
                // a malformed escape: skip this one
            }
        }
        return out
    }

    // files dropped on the tray join the favourites; the panel stays open as for a queue drop
    function addFavorites(urls) {
        dropped = true
        const next = favorites.slice()
        for (const p of pathsOf(urls)) {
            if (next.indexOf(p) < 0)
                next.push(p)
        }
        setFavorites(next)
    }

    function removeFavorite(path) {
        setFavorites(favorites.filter(p => p !== path))
    }

    function setFavorites(next) {
        favorites = next
        favFile.setText(next.join("\n") + "\n")
        statFavorites()
    }

    // the URI a tray card carries when it is dragged, with each name escaped
    function fileUrl(path) {
        return "file://" + path.split("/").map(encodeURIComponent).join("/")
    }

    // a tray file opens in whatever the desktop uses for it; one detached process per file,
    // so a second file is not held until the first (mpv, say) closes
    function openFile(path) {
        Quickshell.execDetached(["xdg-open", path])
    }

    function addUrls(urls) {
        dropped = true
        for (const p of pathsOf(urls))
            addFile(p)
    }

    function removeFile(path) {
        queuedFiles = queuedFiles.filter(p => p !== path)
    }

    function clearQueue() {
        queuedFiles = []
    }

    // Whenever queuedFiles updates, calculate total file count and size in the background
    onQueuedFilesChanged: {
        if (queuedFiles.length === 0) {
            totalFileCount = 0
            totalSize = 0
            return
        }
        statProc.command = ["python3", "-c", `
import sys, os
paths = sys.argv[1:]
tf, ts = 0, 0
for p in paths:
    if os.path.isdir(p):
        for r, ds, fs in os.walk(p):
            for f in fs:
                fp = os.path.join(r, f)
                if os.path.isfile(fp):
                    try:
                        ts += os.path.getsize(fp)
                        tf += 1
                    except: pass
    elif os.path.isfile(p):
        try:
            ts += os.path.getsize(p)
            tf += 1
        except: pass
print(f"{tf}|{ts}")
`].concat(queuedFiles)
        statProc.running = true
    }

    Process {
        id: notifyProc
    }

    Process {
        id: statProc
        stdout: StdioCollector { id: statOut }
        onExited: exitCode => {
            if (exitCode === 0) {
                const parts = statOut.text.trim().split("|")
                if (parts.length === 2) {
                    root.totalFileCount = parseInt(parts[0]) || 0
                    root.totalSize = parseFloat(parts[1]) || 0
                }
            }
        }
    }

    // Process queue: recursively expand any directories into all subfiles, then send
    function send() {
        if (expanding || sending || queuedFiles.length === 0 || selectedDevice === "")
            return
        expanding = true
        lastError = ""

        expandProc.command = ["python3", "-c", `
import sys, os

paths = sys.argv[1:]
final_paths = []

for p in paths:
    if os.path.isdir(p):
        for root_dir, dirs, files in os.walk(p):
            for file in files:
                file_path = os.path.join(root_dir, file)
                if os.path.isfile(file_path):
                    final_paths.append(os.path.abspath(file_path))
    elif os.path.isfile(p):
        final_paths.append(os.path.abspath(p))

for fp in final_paths:
    print(fp)
`].concat(queuedFiles)
        expandProc.running = true
    }

    Process {
        id: expandProc
        stdout: StdioCollector { id: expandOut }
        stderr: StdioCollector { id: expandErr }
        onExited: exitCode => {
            root.expanding = false
            if (exitCode !== 0) {
                const err = expandErr.text.trim() || expandOut.text.trim()
                root.lastError = err !== "" ? err : "expanding directories failed (exit " + exitCode + ")"
                return
            }

            const outputFiles = expandOut.text.trim().split("\n").filter(p => p.trim() !== "")
            if (outputFiles.length === 0) {
                root.lastError = "No valid files to send."
                return
            }

            root.sending = true
            sendProc.command = ["localsend-cli", "send", selectedDevice].concat(outputFiles)
            sendProc.running = true
        }
    }

    Process {
        id: sendProc
        stdout: StdioCollector { id: sendOut }
        stderr: StdioCollector { id: sendErr }
        onExited: exitCode => {
            root.sending = false
            if (exitCode === 0) {
                const count = root.totalFileCount
                const sizeStr = root.formatSize(root.totalSize)
                const label = count === 1 ? "1 file" : count + " files"
                root.notify("Transfer Complete", "Sent " + label + " (" + sizeStr + ")", "normal")
                root.clearQueue()
                root.close()
                return
            }
            const err = sendErr.text.trim() || sendOut.text.trim()
            const msg = err !== "" ? err : "exit " + exitCode
            root.lastError = msg
            root.notify("Transfer Failed", msg, "critical")
        }
    }
}
