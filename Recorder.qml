import QtQuick
import Quickshell
import Quickshell.Io

Item {
    id: root

    width: 0
    height: 0

    readonly property string script: "/home/waltz/.local/bin/record"
    property bool recording: false
    property int elapsed: 0

    function fmt(s) {
        const h = Math.floor(s / 3600)
        const m = Math.floor((s % 3600) / 60)
        const r = s % 60
        const rr = String(r).padStart(2, "0")
        return h > 0
            ? h + ":" + String(m).padStart(2, "0") + ":" + rr
            : m + ":" + rr
    }

    function start() {
        if (!recording)
            Quickshell.execDetached(["sh", "-c", script])
    }

    // SIGINT lets wf-recorder finish writing the file
    function stop() {
        Quickshell.execDetached(["pkill", "-INT", "-x", "wf-recorder"])
    }

    function toggle() {
        recording ? stop() : start()
    }

    // `ps -o etimes=` prints seconds since the process started; empty means no recorder
    function parse(out) {
        const s = parseInt(out.trim())
        recording = !isNaN(s)
        elapsed = recording ? s : 0
    }

    Process {
        id: probe
        command: ["sh", "-c", "ps -o etimes= -C wf-recorder | head -n 1"]
        stdout: StdioCollector {
            id: probeOut
            onStreamFinished: root.parse(probeOut.text)
        }
    }

    Timer {
        interval: 1000
        repeat: true
        running: true
        triggeredOnStart: true
        onTriggered: probe.running = true
    }
}
