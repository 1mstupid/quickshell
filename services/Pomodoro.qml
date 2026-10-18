pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

// Pomodoro timer. The state file holds "endMs minutes remaining", so a running
// or paused timer survives bar restarts; the file is watched so `echo` edits
// take effect. Idle = end 0 and remaining 0; paused = end 0 and remaining > 0.
Singleton {
    id: root

    readonly property string stateFile: Quickshell.env("HOME") + "/.local/xdg/config/pomodoro"
    readonly property string alarmSound: Quickshell.env("HOME")
        + "/.local/state/home-manager/gcroots/current-home/home-path/share/sounds/freedesktop/stereo/alarm-clock-elapsed.oga"

    property int minutes: 25
    readonly property int total: minutes * 60
    property double endMs: 0     // set while running
    property int remaining: 0    // seconds left while running or paused
    property bool done: false    // brief finished state after the alarm

    readonly property bool running: endMs > 0
    readonly property bool paused: !running && remaining > 0
    readonly property bool active: running || paused
    readonly property real fraction: done ? 1 : active ? remaining / total : 0

    function persist() {
        Quickshell.execDetached(["sh", "-c",
            "printf '%s %s %s\\n' " + Math.round(endMs) + " " + minutes + " " + remaining +
            " > '" + stateFile + "'"])
    }

    function begin(secs) {
        done = false
        remaining = secs
        endMs = Date.now() + secs * 1000
        persist()
    }

    function start() {
        if (!active)
            begin(total)
    }

    function pause() {
        if (!running)
            return
        remaining = Math.max(0, Math.round((endMs - Date.now()) / 1000))
        endMs = 0
        persist()
    }

    function resume() {
        if (paused)
            begin(remaining)
    }

    function stop() {
        endMs = 0
        remaining = 0
        done = false
        persist()
    }

    // used by the bar ring: pauses or resumes
    function toggle() {
        if (running)
            pause()
        else if (paused)
            resume()
        else
            start()
    }

    function finish() {
        endMs = 0
        remaining = 0
        done = true
        persist()
        doneTimer.restart()
        Quickshell.execDetached(["paplay", "--volume=40000", alarmSound])
        Quickshell.execDetached(["notify-send", "-u", "critical",
            "Pomodoro", "Time's up — take a break"])
    }

    // the finished state lingers briefly, then hides
    Timer {
        id: doneTimer
        interval: 2500
        onTriggered: root.done = false
    }

    FileView {
        path: root.stateFile
        watchChanges: true
        onFileChanged: reload()
        onLoaded: {
            const parts = text().trim().split(/\s+/)
            const end = parseFloat(parts[0]) || 0
            const mins = parseInt(parts[1]) || 0
            const left = parseInt(parts[2]) || 0
            if (mins >= 1 && mins <= 90)
                root.minutes = mins
            if (end > Date.now()) {
                root.endMs = end
                root.remaining = Math.round((end - Date.now()) / 1000)
            } else {
                // paused keeps its saved remaining time; expired or idle clears it
                root.endMs = 0
                root.remaining = end === 0 ? Math.min(left, root.total) : 0
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

    IpcHandler {
        target: "pomodoro"
        function start(): void { root.start() }
        function pause(): void { root.pause() }
        function resume(): void { root.resume() }
        function stop(): void { root.stop() }
        function toggle(): void { root.toggle() }
    }
}
