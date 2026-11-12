pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import "PortsParse.js" as PortsParse

// What is listening on this machine, read from ss (see PortsParse.js). ss only
// runs while something shows the list: it sets `watching`, and the list then
// refreshes every few seconds until it is cleared. Nothing runs in the meantime.
Singleton {
    id: root

    property bool watching: false
    property var ports: []
    // false until the first answer, so an empty list is not shown as "nothing listening" too early
    property bool loaded: false
    readonly property int exposedCount: ports.filter(p => p.exposed).length

    // a line of feedback for a few seconds, like "copied localhost:3000"
    property string note: ""

    function refresh() {
        if (probe.running)
            return
        probe.running = true
        // ss should answer at once, but a probe that hangs would block every refresh after it
        guard.restart()
    }

    onWatchingChanged: if (watching) refresh()

    function copy(p) {
        const addr = PortsParse.addressOf(p)
        Quickshell.execDetached(["wl-copy", "--", addr])
        note = "copied " + addr
        noteTimer.restart()
    }

    Timer {
        interval: 3000
        repeat: true
        running: root.watching
        onTriggered: root.refresh()
    }

    Timer {
        id: guard
        interval: 4000
        onTriggered: probe.running = false
    }

    Timer {
        id: noteTimer
        interval: 2200
        onTriggered: root.note = ""
    }

    // both commands in one process, so the answers arrive together
    Process {
        id: probe
        command: ["sh", "-c",
            "ss -tulpnH 2>/dev/null; echo '" + PortsParse.MARK + "'; ss -tnH state established 2>/dev/null"]
        stdout: StdioCollector {
            onStreamFinished: {
                guard.stop()
                root.ports = PortsParse.parse(text)
                root.loaded = true
            }
        }
    }
}
