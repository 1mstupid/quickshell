pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

// Bedtime reminders, read from ~/.local/xdg/config/sleep-reminder:
//   warn 20:00
//   bed 21:00
// Each line fires one notification a day when the clock reaches it. No file,
// or a missing line, turns that reminder off.
Singleton {
    id: root

    readonly property string path: Quickshell.env("HOME") + "/.local/xdg/config/sleep-reminder"

    property string warnAt: ""
    property string bedAt: ""
    // the day each reminder last fired, so it fires once per day
    property var sent: ({ warn: "", bed: "" })

    function dayKey() { return Qt.formatDate(new Date(), "yyyy-MM-dd") }

    function parse(t) {
        let w = ""
        let b = ""
        for (const line of t.split("\n")) {
            const p = line.trim().split(/\s+/)
            if (p.length < 2)
                continue
            if (p[0] === "warn")
                w = p[1]
            else if (p[0] === "bed")
                b = p[1]
        }
        warnAt = w
        bedAt = b
    }

    function tick() {
        const now = Qt.formatTime(new Date(), "HH:mm")
        const day = dayKey()
        if (warnAt !== "" && now === warnAt && sent.warn !== day) {
            sent.warn = day
            Quickshell.execDetached(["notify-send", "-u", "normal", "Sleep",
                "Wind down, bedtime at " + bedAt])
        }
        if (bedAt !== "" && now === bedAt && sent.bed !== day) {
            sent.bed = day
            Quickshell.execDetached(["notify-send", "-u", "critical", "Sleep",
                "Time for bed"])
        }
    }

    // 30 s is shorter than a minute, so every minute gets at least one tick
    Timer {
        interval: 30000
        repeat: true
        running: true
        onTriggered: root.tick()
    }

    FileView {
        path: root.path
        watchChanges: true
        onFileChanged: reload()
        onLoaded: root.parse(text())
        onLoadFailed: root.parse("")
    }
}
