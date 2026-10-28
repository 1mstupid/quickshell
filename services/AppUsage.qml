pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

// App focus time, from `umbriel subscribe windows`. The window with
// active: true holds keyboard focus, and its elapsed time goes to its app_id.
// Focus time is time a listed app (focus-apps.json) has focus, or any time a
// pomodoro runs; it is kept in 5-minute slots for the focus widget and the
// Pomodoro page. Totals per day live in
// app-usage.json; limits in app-limits, one "app_id minutes" line each. A limit
// notifies at 80% and at 100%, once each.
Singleton {
    id: root

    readonly property string dir: Quickshell.env("HOME") + "/.local/xdg/config"
    readonly property int keepDays: 7
    // longer gaps (suspend, a stalled shell) are not counted as use
    readonly property int maxGapMs: 90000

    // { "2026-10-25": { "seconds": { "helium": 1234.5 }, "alerted": ["helium:80"],
    //   "focus": { "132": 240 } } }   focus: seconds per 5-minute slot from midnight
    property var days: ({})
    // { "helium": 60 } in minutes
    property var limits: ({})
    // app ids whose focus time counts toward the focus widget; a pomodoro always counts
    property var focusApps: []
    // bumped whenever the numbers change, so bindings re-read them
    property int revision: 0

    property string currentApp: ""
    property double lastMs: Date.now()
    property bool ready: false
    property bool dirty: false
    // the desktop widget; toggled from the Usage tab or `qs ipc call usage toggle`
    property bool widgetShown: true
    // the focus widget on the wallpaper; toggled from the Pomodoro page
    property bool focusWidgetShown: true

    function toggleWidget() { widgetShown = !widgetShown }
    function toggleFocusWidget() { focusWidgetShown = !focusWidgetShown }

    // the window list from the last event, re-checked on each tick
    property var lastWindows: []
    // window id -> ms of its last close request, kept only for open windows
    property var closeSent: ({})

    // an app is blocked from the moment its total reaches its limit, until
    // midnight. The app id goes into the day's "blocked" list, so raising the
    // limit later does not lift it, and reopened windows (new ids) are caught.
    function blocked(app) {
        const rec = days[dayKey()]
        if (!rec)
            return false
        rec.blocked = rec.blocked ?? []
        if (rec.blocked.indexOf(app) >= 0)
            return true
        const lim = limits[app]
        if (lim && (rec.seconds[app] ?? 0) / 60 >= lim) {
            rec.blocked.push(app)
            dirty = true
            return true
        }
        return false
    }

    // ask each open window of a blocked app to close, retrying every 10 s
    // while it stays open (an app may show a save prompt first)
    function enforce(list) {
        const now = Date.now()
        const next = {}
        for (const w of list) {
            const last = closeSent[w.id] ?? 0
            if (blocked(w.app_id) && now - last >= 10000) {
                Quickshell.execDetached(["umbriel", "msg", "window-close:" + w.id])
                next[w.id] = now
            } else if (last) {
                next[w.id] = last
            }
        }
        closeSent = next
    }

    function dayKey() { return Qt.formatDate(new Date(), "yyyy-MM-dd") }

    function fmt(sec) {
        const m = Math.floor(sec / 60)
        const h = Math.floor(m / 60)
        return h > 0 ? h + "h " + (m % 60) + "m" : m + "m"
    }

    // h:mm:ss, as the Pomodoro page shows the day's focus time
    function fmtHms(sec) {
        const s = Math.floor(sec)
        const h = Math.floor(s / 3600)
        const m = Math.floor((s % 3600) / 60)
        return h + ":" + String(m).padStart(2, "0") + ":" + String(s % 60).padStart(2, "0")
    }

    // 5-minute slot of the day for a time: 0 = 00:00, 287 = 23:55
    function slotOf(ms) {
        const d = new Date(ms)
        return d.getHours() * 12 + Math.floor(d.getMinutes() / 5)
    }

    // seconds of focus per slot for a day, keyed by slot index
    // a fresh copy each time, so bindings see a change when revision bumps
    function focusSlots(key, rev) {
        const r = days[key]
        return (r && r.focus) ? Object.assign({}, r.focus) : {}
    }

    function focusTotal(key, rev) {
        const f = focusSlots(key, rev)
        return Object.keys(f).reduce((s, k) => s + f[k], 0)
    }

    // one row per app for a day, most used first
    function totals(key, rev) {
        const r = days[key]
        if (!r)
            return []
        return Object.keys(r.seconds)
            .map(a => ({ app: a, sec: r.seconds[a] }))
            .sort((a, b) => b.sec - a.sec)
    }

    function notify(app, msg, urgency) {
        Quickshell.execDetached(["notify-send", "-u", urgency, "App time", app + " " + msg])
    }

    function check(key, app) {
        const lim = limits[app]
        if (!lim)
            return
        const rec = days[key]
        const spent = rec.seconds[app] / 60
        if (spent >= lim && rec.alerted.indexOf(app + ":100") < 0) {
            rec.alerted.push(app + ":100")
            notify(app, "reached its " + lim + " min limit", "critical")
        } else if (spent >= lim * 0.8 && rec.alerted.indexOf(app + ":80") < 0) {
            rec.alerted.push(app + ":80")
            notify(app, "is at 80% of its " + lim + " min limit", "normal")
        }
    }

    // credit the time since the last tick. It is focus time when a window has
    // focus or a pomodoro runs; the app with focus also gets it.
    function credit() {
        const now = Date.now()
        const dt = now - lastMs
        lastMs = now
        if (!ready || dt <= 0 || dt > maxGapMs)
            return
        const focused = focusApps.indexOf(currentApp) >= 0
        if (currentApp === "" && !Pomodoro.running)
            return
        const key = dayKey()
        if (!days[key])
            days[key] = { seconds: {}, alerted: [], blocked: [], focus: {} }
        const rec = days[key]
        rec.focus = rec.focus ?? {}
        if (focused || Pomodoro.running) {
            const slot = slotOf(now)
            rec.focus[slot] = (rec.focus[slot] ?? 0) + dt / 1000
        }
        if (currentApp !== "") {
            rec.seconds[currentApp] = (rec.seconds[currentApp] ?? 0) + dt / 1000
            check(key, currentApp)
        }
        dirty = true
    }

    function onWindows(line) {
        let msg
        try {
            msg = JSON.parse(line)
        } catch (e) {
            return
        }
        if (msg.event !== "windows")
            return
        credit()
        const w = msg.data.find(x => x.active === true)
        currentApp = w ? w.app_id : ""
        lastWindows = msg.data
        enforce(lastWindows)
        revision++
    }

    function flush() {
        if (!dirty)
            return
        dirty = false
        const keys = Object.keys(days).sort()
        while (keys.length > keepDays)
            delete days[keys.shift()]
        store.setText(JSON.stringify(days, null, 2) + "\n")
    }

    function parseLimits(t) {
        const m = {}
        for (const line of t.split("\n")) {
            const p = line.trim().split(/\s+/)
            if (p.length >= 2 && parseInt(p[1]) > 0)
                m[p[0]] = parseInt(p[1])
        }
        limits = m
    }

    Component.onCompleted: revision++

    IpcHandler {
        target: "usage"
        function toggle(): void { root.toggleWidget() }
        function toggleFocus(): void { root.toggleFocusWidget() }
    }

    Process {
        id: sub
        command: ["umbriel", "subscribe", "windows"]
        running: true
        stdout: SplitParser {
            onRead: line => root.onWindows(line)
        }
        onExited: restart.restart()
    }

    Timer {
        id: restart
        interval: 1000
        onTriggered: sub.running = true
    }

    // once a second, so the focus counter ticks live; credit() only adds time
    // that has really passed, so a slow tick never over-counts
    Timer {
        interval: 1000
        repeat: true
        running: true
        onTriggered: {
            root.credit()
            root.revision++
        }
    }

    // every 30 s: enforce limits, save to disk, and roll the day over at midnight
    Timer {
        interval: 30000
        repeat: true
        running: true
        onTriggered: {
            root.credit()
            root.enforce(root.lastWindows)
            root.flush()
            root.revision++
        }
    }

    FileView {
        id: store
        path: root.dir + "/app-usage.json"
        atomicWrites: true
        onLoaded: {
            let d = null
            try {
                d = JSON.parse(text())
            } catch (e) {
                d = null
            }
            root.days = (d && typeof d === "object") ? d : {}
            root.ready = true
            root.revision++
        }
        onLoadFailed: {
            root.days = {}
            root.ready = true
        }
    }

    FileView {
        path: root.dir + "/app-limits"
        watchChanges: true
        onFileChanged: reload()
        onLoaded: root.parseLimits(text())
        onLoadFailed: root.limits = {}
    }

    // a JSON array of app ids, e.g. ["helium", "code"]; a bad file counts as empty
    FileView {
        path: root.dir + "/focus-apps.json"
        watchChanges: true
        onFileChanged: reload()
        onLoaded: {
            let a = []
            try {
                a = JSON.parse(text())
            } catch (e) {
                a = []
            }
            root.focusApps = Array.isArray(a) ? a : []
        }
        onLoadFailed: root.focusApps = []
    }
}
