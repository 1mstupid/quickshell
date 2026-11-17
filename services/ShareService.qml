pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

// Outgoing file shares through localsend-cli. Files queue here and go in one
// send to the phone's IP. The CLI can't find devices on this network, so the
// IP is set by hand, e.g. the phone's Tailscale address.
Singleton {
    id: root

    // paths waiting to be sent, in the order they were added
    property var queuedFiles: []
    // IP of the destination phone; empty until one is chosen
    property string selectedDevice: ""
    property bool sending: false
    // why the last send failed; empty after a success or before any send
    property string lastError: ""

    // a path already in the queue is not added twice
    function addFile(path) {
        if (path === "" || queuedFiles.indexOf(path) >= 0)
            return
        queuedFiles = queuedFiles.concat([path])
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
                return
            }
            const err = sendErr.text.trim() || sendOut.text.trim()
            root.lastError = err !== "" ? err : "exit " + exitCode
        }
    }
}
