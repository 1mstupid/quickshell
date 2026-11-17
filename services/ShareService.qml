pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

// Outgoing file shares through localsend-cli. Files queue here and go in one send to
// the phone's IP. The CLI can't find devices on this network, so the IP is fixed in
// settings.json, e.g. {"shareDevice": "100.117.26.7"} (a Tailscale address). A file
// dragged onto the bar pill or the share panel queues it and opens the panel.
Singleton {
    id: root

    // the destination; empty until settings.json names one
    readonly property string selectedDevice: {
        const d = UserSettings.extra.shareDevice
        return typeof d === "string" ? d.trim() : ""
    }

    // paths waiting to be sent, in the order they were added
    property var queuedFiles: []
    property bool sending: false
    // why the last send failed; empty after a success or before any send
    property string lastError: ""

    // the share panel is open; a drag that leaves without a drop closes it after a short wait
    property bool panelOpen: false

    function open() {
        closeTimer.stop()
        panelOpen = true
    }

    function scheduleClose() {
        if (panelOpen)
            closeTimer.restart()
    }

    function cancelClose() {
        closeTimer.stop()
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

    // a path already in the queue is not added twice
    function addFile(path) {
        if (path === "" || queuedFiles.indexOf(path) >= 0)
            return
        queuedFiles = queuedFiles.concat([path])
    }

    // drop URLs are file:// URIs; anything else is ignored
    function addUrls(urls) {
        for (let i = 0; i < urls.length; i++) {
            const s = String(urls[i])
            if (s.indexOf("file://") !== 0)
                continue
            try {
                addFile(decodeURIComponent(s.slice(7)))
            } catch (e) {
                // a malformed escape: skip this one
            }
        }
    }

    function removeFile(path) {
        queuedFiles = queuedFiles.filter(p => p !== path)
    }

    function clearQueue() {
        queuedFiles = []
    }

    // one CLI call for the whole queue; the queue is kept unless the send succeeds
    function send() {
        if (sending || queuedFiles.length === 0 || selectedDevice === "")
            return
        sending = true
        lastError = ""
        // arguments go straight to the process, never through a shell, so file names are safe
        sendProc.command = ["localsend-cli", "send", selectedDevice].concat(queuedFiles)
        sendProc.running = true
    }

    Process {
        id: sendProc
        stdout: StdioCollector { id: sendOut }
        stderr: StdioCollector { id: sendErr }
        onExited: exitCode => {
            root.sending = false
            if (exitCode === 0) {
                root.clearQueue()
                root.close()
                return
            }
            const err = sendErr.text.trim() || sendOut.text.trim()
            root.lastError = err !== "" ? err : "exit " + exitCode
        }
    }
}
