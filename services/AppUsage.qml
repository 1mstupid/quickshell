pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

// App focus time, from `umbriel subscribe windows`. The window with
// active: true holds keyboard focus, and its elapsed time goes to its app_id.
// Focus time is time a listed app (focus-apps.json) has focus, or any time a
// pomodoro runs; it is kept in 5-minute slots for the focus widget and the
// Pomodoro page. Totals per day live in
// app-usage.json; categories in app-categories, one "app_id category" line each;
// limits in app-limits, one "app_id minutes" line each. A limit
// notifies at 80% and at 100%, once each.
Singleton {
    id: root

    readonly property string dir: Quickshell.env("HOME") + "/.local/xdg/config"
    readonly property int keepDays: 31
    // longer gaps (suspend, a stalled shell) are not counted as use
    readonly property int maxGapMs: 90000

    // { "2026-10-25": { "seconds": { "helium": 1234.5 }, "alerted": ["helium:80"],
    //   "focus": { "132": 240 }, "hours": { "9": { "helium": 600 } },
    //   "sessions": [{ "app": "helium", "start": 1761731400000, "end": 1761732000000 }],
    //   "notifications": 3 } }
    //   focus: seconds per 5-minute slot from midnight; hours: seconds per clock hour
    //   per app; sessions: one entry per focus stretch, recorded when focus moves on
    property var days: ({})
    // { "helium": 60 } in minutes
    property var limits: ({})
    // { "helium": "Internet" } from app-categories; unlisted apps are "Other"
    property var categories: ({})
    // app ids whose focus time counts toward the focus widget; a pomodoro always counts
    property var focusApps: []
    // bumped whenever the numbers change, so bindings re-read them
    property int revision: 0

    property string currentApp: ""
    // when the current app got focus; the session is recorded when focus moves on
    property double sessionStart: Date.now()
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

    // the day's record, created or topped up with any field it is missing
    function ensureDay(key) {
        const rec = days[key] ?? {}
        rec.seconds = rec.seconds ?? {}
        rec.alerted = rec.alerted ?? []
        rec.blocked = rec.blocked ?? []
        rec.focus = rec.focus ?? {}
        rec.hours = rec.hours ?? {}
        rec.sessions = rec.sessions ?? []
        rec.runs = rec.runs ?? []
        rec.notifications = rec.notifications ?? 0
        days[key] = rec
        return rec
    }

    // the last n day keys, oldest first, ending today. Takes rev like the other
    // readers, so bindings that call it refresh every tick and roll over at midnight.
    function dayKeys(n, rev) {
        const today = new Date()
        const out = []
        for (let i = n - 1; i >= 0; i--)
            out.push(Qt.formatDate(new Date(today.getFullYear(), today.getMonth(), today.getDate() - i), "yyyy-MM-dd"))
        return out
    }

    // per-day readers, in the same style as focusSlots and pomodoros
    function hoursOf(key, rev) {
        const r = days[key]
        return (r && r.hours) ? r.hours : {}
    }

    function sessionsOf(key, rev) {
        const r = days[key]
        return (r && r.sessions) ? r.sessions : []
    }

    // pomodoro work runs: {start, end} in ms, one per run, recorded when the run stops
    function runsOf(key, rev) {
        const r = days[key]
        return (r && r.runs) ? r.runs : []
    }

    function addPomodoroRun(start, end) {
        if (!ready || end - start < 1000)
            return
        const rec = ensureDay(dayKey())
        rec.runs.push({ start: start, end: end })
        dirty = true
        revision++
    }

    function notificationsOf(key, rev) {
        const r = days[key]
        return r ? (r.notifications ?? 0) : 0
    }

    // every notification that arrives counts, the shell's own included
    function countNotification() {
        if (!ready)
            return
        const rec = ensureDay(dayKey())
        rec.notifications += 1
        dirty = true
        revision++
    }

    // H:MM for every usage total and limit, e.g. 0:05, 1:20, 12:00
    function fmt(sec) {
        const m = Math.floor(sec / 60)
        return Math.floor(m / 60) + ":" + String(m % 60).padStart(2, "0")
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

    // work sessions finished on a day
    function pomodoros(key, rev) {
        const r = days[key]
        return r ? (r.pomodoros ?? 0) : 0
    }

    function addPomodoro() {
        const rec = ensureDay(dayKey())
        rec.pomodoros = (rec.pomodoros ?? 0) + 1
        dirty = true
        revision++
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
        const rec = ensureDay(key)
        if (focused || Pomodoro.running) {
            const slot = slotOf(now)
            rec.focus[slot] = (rec.focus[slot] ?? 0) + dt / 1000
        }
        if (currentApp !== "") {
            // the whole interval goes to the hour it ends in, which is exact
            // except for the one tick that straddles an hour boundary
            const hour = new Date(now).getHours()
            rec.seconds[currentApp] = (rec.seconds[currentApp] ?? 0) + dt / 1000
            rec.hours[hour] = rec.hours[hour] ?? {}
            rec.hours[hour][currentApp] = (rec.hours[hour][currentApp] ?? 0) + dt / 1000
            check(key, currentApp)
        }
        dirty = true
    }

    // a focus stretch ends: keep it if it lasted at least a second. Recorded
    // under the day it ends on, so one that crosses midnight lands on the later day.
    function endSession(now) {
        if (!ready || currentApp === "" || now - sessionStart < 1000)
            return
        const rec = ensureDay(dayKey())
        rec.sessions.push({ app: currentApp, start: sessionStart, end: now })
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
        const app = w ? w.app_id : ""
        if (app !== currentApp) {
            const now = Date.now()
            endSession(now)
            currentApp = app
            sessionStart = now
        }
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

    // "app_id category" per line; the category may hold spaces
    function parseCategories(t) {
        const m = {}
        for (const line of t.split("\n")) {
            const p = line.trim().split(/\s+/)
            if (p.length >= 2)
                m[p[0]] = p.slice(1).join(" ")
        }
        categories = m
    }

    function categoryOf(app) {
        return categories[app] ?? "Other"
    }

    // seconds per category for a day, most used first. Looked up at read time,
    // so editing app-categories also re-sorts past days.
    function categoryTotals(key, rev) {
        const r = days[key]
        if (!r)
            return []
        const sums = {}
        for (const app of Object.keys(r.seconds)) {
            const c = categoryOf(app)
            sums[c] = (sums[c] ?? 0) + r.seconds[app]
        }
        return Object.keys(sums)
            .map(c => ({ category: c, sec: sums[c] }))
            .sort((a, b) => b.sec - a.sec)
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

    // one "app_id category" per line; a missing file means everything is "Other"
    FileView {
        path: root.dir + "/app-categories"
        watchChanges: true
        onFileChanged: reload()
        onLoaded: root.parseCategories(text())
        onLoadFailed: root.categories = {}
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
