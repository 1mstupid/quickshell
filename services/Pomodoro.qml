pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

// Pomodoro timer with study cycles. A cycle is four work sessions: after each
// of the first three comes a short break, after the fourth a long break. Work
// sessions are counted per day in AppUsage, which also drives the dots.
// Durations come from ~/.local/xdg/config/pomodoro-config ("work", "short" and
// "long" lines, in minutes).
//
// The state file holds "endMs minutes remaining phase override", so a running or paused
// timer survives bar restarts; the file is watched so `echo` edits take effect.
// Idle = end 0 and remaining 0; paused = end 0 and remaining > 0. The minutes
// field is informational and not read back; override is the hand-set length (0 = config).
Singleton {
    id: root

    readonly property string stateFile: Quickshell.env("HOME") + "/.local/xdg/config/pomodoro"
    readonly property string configFile: Quickshell.env("HOME") + "/.local/xdg/config/pomodoro-config"
    readonly property string alarmSound: Quickshell.env("HOME")
        + "/.local/state/home-manager/gcroots/current-home/home-path/share/sounds/freedesktop/stereo/alarm-clock-elapsed.oga"

    // durations in minutes, from the config file; these defaults are the standard 30-5-15
    property int workMin: 30
    property int shortMin: 5
    property int longMin: 15

    // "work", "short" or "long": the session the timer is on, running or idle
    property string phase: "work"
    // minutes set by hand for the idle session; 0 uses the config value
    property int override: 0
    readonly property int configured: phase === "work" ? workMin
        : phase === "short" ? shortMin : longMin
    readonly property int minutes: override > 0 ? override : configured
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
            "printf '%s %s %s %s %s\\n' " + Math.round(endMs) + " " + minutes + " " + remaining
            + " " + phase + " " + override + " > '" + stateFile + "'"])
    }

    // steps the session length by hand, in 5-minute steps, while idle
    function adjust(delta) {
        if (active)
            return
        override = Math.max(1, Math.min(90, minutes + delta))
        persist()
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

    // ends the current session without counting it; the phase stays
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

    // a finished work session counts and leads to a break; a finished break
    // leads back to work. The next session waits for the user to start it.
    function finish() {
        const finished = phase
        endMs = 0
        remaining = 0
        done = true
        // a hand-set length is for one session only
        override = 0
        if (finished === "work") {
            AppUsage.addPomodoro()
            const sets = AppUsage.pomodoros(AppUsage.dayKey(), AppUsage.revision)
            phase = sets % 4 === 0 ? "long" : "short"
        } else {
            phase = "work"
        }
        persist()
        doneTimer.restart()
        Quickshell.execDetached(["paplay", "--volume=40000", alarmSound])
        Quickshell.execDetached(["notify-send", "-u", "critical", "Pomodoro",
            finished === "work"
                ? "Session done, take a " + (phase === "long" ? "long" : "short") + " break"
                : "Break over, back to work"])
    }

    // the finished state lingers briefly, then hides
    Timer {
        id: doneTimer
        interval: 2500
        onTriggered: root.done = false
    }

    // reads the durations; any line that is missing or not a sane number keeps its default
    function parseConfig(t) {
        const v = { work: 30, short: 5, long: 15 }
        for (const line of t.split("\n")) {
            const p = line.trim().split(/\s+/)
            if (p.length < 2 || !(p[0] in v))
                continue
            const n = parseInt(p[1])
            if (n >= 1 && n <= 180)
                v[p[0]] = n
        }
        workMin = v.work
        shortMin = v.short
        longMin = v.long
    }

    FileView {
        path: root.configFile
        watchChanges: true
        onFileChanged: reload()
        onLoaded: root.parseConfig(text())
        onLoadFailed: root.parseConfig("")
    }

    FileView {
        path: root.stateFile
        watchChanges: true
        onFileChanged: reload()
        onLoaded: {
            const parts = text().trim().split(/\s+/)
            const end = parseFloat(parts[0]) || 0
            const set = parseInt(parts[4]) || 0
            root.override = set >= 1 && set <= 90 ? set : 0
            const left = parseInt(parts[2]) || 0
            if (["work", "short", "long"].indexOf(parts[3]) >= 0)
                root.phase = parts[3]
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
