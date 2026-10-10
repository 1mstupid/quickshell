import QtQuick
import Quickshell
import Quickshell.Io

Item {
    id: root

    readonly property string stateFile: "/home/waltz/.local/xdg/config/pomodoro"
    readonly property string alarmSound: "/home/waltz/.local/state/home-manager/gcroots/current-home/home-path/share/sounds/freedesktop/stereo/alarm-clock-elapsed.oga"
    readonly property var presets: [1, 10, 25, 45, 60]

    property int minutes: 25
    readonly property int total: minutes * 60
    property double endMs: 0
    property int remaining: total
    property bool done: false
    readonly property bool running: endMs > 0

    // what the drain bar shows: full when idle, shrinking while running
    readonly property real fraction: running ? remaining / total : (done ? 0 : 1)


    function fmt(s) {
        return Math.floor(s / 60) + ":" + String(s % 60).padStart(2, "0")
    }

    // end-timestamp + minutes in a plain state file so a running timer
    // survives bar restarts; the FileView below watches it for outside edits
    function persist() {
        Quickshell.execDetached(["sh", "-c",
            "printf '%s %s\\n' " + Math.round(endMs) + " " + minutes +
            " > '" + stateFile + "'"])
    }

    function start() {
        done = false
        endMs = Date.now() + total * 1000
        remaining = total
        persist()
    }

    function stop() {
        endMs = 0
        remaining = total
        persist()
    }

    function toggle() {
        running ? stop() : start()
    }

    function finish() {
        endMs = 0
        remaining = 0
        done = true
        persist()
        // chime plays regardless of DND; the notification lands in
        // dunst history if DND holds it
        Quickshell.execDetached(["paplay", "--volume=40000", alarmSound])
        Quickshell.execDetached(["notify-send", "-u", "critical",
            "Pomodoro", "Time's up — take a break"])
    }

    // right-click: next preset above the current duration, wrapping around
    function cyclePreset() {
        if (running) return
        const next = presets.find(m => m > minutes)
        minutes = next !== undefined ? next : presets[0]
        persist()
    }

    // scroll: ±5 min, clamped to 1–90
    function nudge(dir) {
        if (running) return
        minutes = Math.min(90, Math.max(1, minutes + dir * 5))
        persist()
    }

    FileView {
        path: root.stateFile
        watchChanges: true
        onFileChanged: reload()
        onLoaded: {
            const parts = text().trim().split(/\s+/)
            const end = parseFloat(parts[0]) || 0
            const mins = parseInt(parts[1]) || 0
            if (mins >= 1 && mins <= 90)
                root.minutes = mins
            if (end > Date.now()) {
                root.endMs = end
                root.remaining = Math.round((end - Date.now()) / 1000)
            } else {
                // 0 = stopped, or expired while the bar was down: stay idle
                root.endMs = 0
            }
        }
    }

    Timer {
        interval: 1000
        repeat: true
        running: root.running
        onTriggered: {
            root.remaining = Math.max(0, Math.round((root.endMs - Date.now()) / 1000))
            if (root.remaining <= 0)
                root.finish()
        }
    }

    // ---- UI ----

    implicitHeight: 92

    Rectangle {
        anchors.fill: parent
        radius: 12
        color: Qt.alpha(Theme.bg, 0.06)
        border.color: Qt.alpha(Theme.accent, 0.3)
        border.width: 0
    }

    // right-click cycles presets, scroll nudges duration
    MouseArea {
        anchors.fill: parent
        acceptedButtons: Qt.RightButton
        onClicked: root.cyclePreset()
        onWheel: (wheel) => root.nudge(wheel.angleDelta.y > 0 ? 1 : -1)
    }

    Text {
        id: heading
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.margins: 10
        text: "POMODORO"
        font.family: Theme.font
        font.pixelSize: 9
        font.bold: true
        font.letterSpacing: 1.5
        color: Qt.alpha(Theme.accent, 0.8)
    }

    Text {
        anchors.top: parent.top
        anchors.right: parent.right
        anchors.margins: 10
        text: root.minutes + "m"
        font.family: Theme.font
        font.pixelSize: 9
        font.bold: true
        color: Qt.alpha(Theme.accent, 0.5)
    }

    Text {
        id: timeText
        anchors.left: parent.left
        anchors.leftMargin: 10
        anchors.top: heading.bottom
        anchors.topMargin: 2
        text: root.done ? "Done" : root.fmt(root.running ? root.remaining : root.total)
        font.family: Theme.font
        font.pixelSize: 22
        font.bold: true
        color: Theme.fg
    }

    Rectangle {
        id: button
        anchors.right: parent.right
        anchors.rightMargin: 10
        anchors.verticalCenter: timeText.verticalCenter
        width: 64
        height: 24
        radius: 12
        color: root.running ? Qt.alpha(Theme.accent, 0.25) : Qt.alpha(Theme.accent, 0.6)

        Text {
            anchors.centerIn: parent
            text: root.running ? "Stop" : "Start"
            font.family: Theme.font
            font.pixelSize: 11
            font.bold: true
            color: Theme.fg
        }

        MouseArea {
            anchors.fill: parent
            cursorShape: Qt.PointingHandCursor
            onClicked: root.toggle()
        }
    }

    Rectangle {
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        anchors.margins: 10
        height: 4
        radius: 2
        color: Qt.alpha(Theme.accent, 0.15)

        Rectangle {
            height: parent.height
            radius: parent.radius
            width: parent.width * root.fraction
            color: Theme.accent
            Behavior on width { NumberAnimation { duration: 250; easing.type: Easing.OutCubic } }
        }
    }
}
