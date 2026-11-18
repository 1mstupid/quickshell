pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

// Bedtime reminders, from the [sleep] table of config.toml:
//   warn = "20:00"
//   bed = "21:00"
// Each one fires one notification a day when the clock reaches it. No table,
// or a missing key, turns that reminder off.
Singleton {
    id: root

    property string warnAt: ""
    property string bedAt: ""
    // the day each reminder last fired, so it fires once per day
    property var sent: ({ warn: "", bed: "" })

    function dayKey() { return Qt.formatDate(new Date(), "yyyy-MM-dd") }

    function apply(table) {
        warnAt = typeof table?.warn === "string" ? table.warn : ""
        bedAt = typeof table?.bed === "string" ? table.bed : ""
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

    Connections {
        target: Config
        function onDataChanged() { root.apply(Config.data.sleep) }
    }
}
