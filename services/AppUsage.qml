pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland
import "menu"

// App focus time, from Hyprland's toplevels. The focused toplevel holds
// keyboard focus, and its elapsed time goes to its app_id.
// Focus time is time an app listed in [focus] apps (config.toml) has focus, or any
// time a pomodoro runs; it is kept in 5-minute slots for the focus widget and the
// Pomodoro page. Totals per day live in app-usage.json in the state folder. Limits,
// categories, schedules and the task gate are tables in config.toml, read by Config.
// A limit notifies at 80% and at 100%, once each.
Singleton {
    id: root

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
    // { "@Games": [{ windows: [{ start: 540, end: 1020 }], days: [1,2,3,4,5] }] }
    property var schedules: ({})
    // targets closed while tasks are owed, and the minutes that clear one
    property var taskGateTargets: []
    property int taskGateMinutes: 10
    // { "helium": "Internet" } from [categories]; unlisted apps are "Other"
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
    // the desktop widget and the focus widget show or hide through layout.json
    // (`qs ipc call usage toggle` / `toggleFocus`, or the layout edit mode)
    function toggleWidget() { WidgetLayout.toggle("usage") }
    function toggleFocusWidget() { WidgetLayout.toggle("focus") }

    // the window list, refreshed when focus moves and on each tick
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

    // focus mode: during a work session, any app not in [focus] apps is
    // blocked. An empty list blocks nothing, so a missing file cannot close everything.
    function outOfFocus(app) {
        return Pomodoro.running && Pomodoro.phase === "work"
            && focusApps.length > 0 && focusApps.indexOf(app) < 0
    }

    function matchesTarget(target, app) {
        if (target.startsWith("@"))
            return categoryOf(app).toLowerCase() === target.slice(1).toLowerCase()
        if (target.endsWith("*"))
            return app.startsWith(target.slice(0, -1))
        return target === app
    }

    // scheduled blocks: matches active time windows from [schedules]
    // (supports exact app_id, prefix*, and @Category targets)
    function scheduledBlock(app) {
        if (!app)
            return false
        const now = new Date()
        const day = now.getDay()
        const yesterday = (day + 6) % 7
        const min = now.getHours() * 60 + now.getMinutes()

        for (const target of Object.keys(schedules)) {
            if (!matchesTarget(target, app))
                continue
            for (const r of schedules[target]) {
                for (const w of r.windows) {
                    if (w.start <= w.end) {
                        if (r.days.indexOf(day) >= 0 && min >= w.start && min < w.end)
                            return true
                    } else {
                        // Overnight window (e.g., 22:30-06:00)
                        if ((r.days.indexOf(day) >= 0 && min >= w.start)
                            || (r.days.indexOf(yesterday) >= 0 && min < w.end))
                            return true
                    }
                }
            }
        }
        return false
    }

    // task gate: while todo.md owes work, the gated targets stay closed. A task
    // is owed when it is open and has less than taskGateMinutes of time (done
    // counts as enough). Time on the task in focus counts live, so the way to
    // unlock an app is to work on the task, not to tick it in a blocked app.
    function tasksOwed() {
        return Todo.upcoming.some(t => {
            const live = TaskFocus.sameTask(t) ? TaskFocus.elapsedMs / 60000 : 0
            return t.spent + live < taskGateMinutes
        })
    }

    function taskGated(app) {
        if (!app || taskGateTargets.length === 0)
            return false
        return taskGateTargets.some(t => matchesTarget(t, app)) && tasksOwed()
    }

    // hyprctl eval finds the window object, which the close dispatcher takes. Hyprland
    // compares addresses without the 0x prefix, so the prefix is stripped here.
    function closeWindow(address) {
        const hex = String(address).replace(/^0x/, "").replace(/[^0-9a-fA-F]/g, "")
        Quickshell.execDetached(["hyprctl", "eval",
            "for _, w in pairs(hl.get_windows()) do "
            + "if tostring(w.address):gsub(\"^0x\", \"\") == \"" + hex + "\" then "
            + "hl.dispatch(hl.dsp.window.close({ window = w })) break end end"])
    }

    // ask each open window of a blocked app to close, retrying every 10 s
    // while it stays open (an app may show a save prompt first). Blocked means
    // over its limit, outside focus mode during a work session, in a scheduled
    // block, or gated by unfinished tasks.
    function enforce(list) {
        const now = Date.now()
        const next = {}
        for (const w of list) {
            const last = closeSent[w.id] ?? 0
            if ((blocked(w.app_id) || outOfFocus(w.app_id) || scheduledBlock(w.app_id)
                    || taskGated(w.app_id)) && now - last >= 10000) {
                closeWindow(w.id)
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

    // focus moved: bank the time of the last app, then start the new one
    function onFocusChanged() {
        credit()
        refreshWindows()
        const w = lastWindows.find(x => x.active === true)
        const app = w ? w.app_id : ""
        if (app !== currentApp) {
            const now = Date.now()
            endSession(now)
            currentApp = app
            sessionStart = now
        }
        enforce(lastWindows)
        revision++
    }

    // the open toplevels in the shape the rules below read: id, app_id, active.
    // Hyprland's own class and address are what windowrules and closewindow use.
    // The Wayland app id is only a fallback: schedules and the task gate skip
    // any window whose app_id is empty.
    function refreshWindows() {
        lastWindows = Hyprland.toplevels.values.map(t => {
            const ipc = t.lastIpcObject ?? {}
            return {
                id: ipc.address ?? t.address,
                app_id: ipc.class || t.wayland?.appId || "",
                active: t.activated === true
            }
        })
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

    // [categories]: app_id or prefix* = "Category"
    function parseCategories(table) {
        const m = {}
        for (const k of Object.keys(table))
            if (typeof table[k] === "string" && table[k].trim() !== "")
                m[k] = table[k].trim()
        categories = m
    }

    function categoryOf(app) {
        if (categories[app])
            return categories[app]
        for (const k of Object.keys(categories)) {
            if (k.endsWith("*") && app.startsWith(k.slice(0, -1)))
                return categories[k]
        }
        return "Other"
    }

    // seconds per category for a day, most used first. Looked up at read time,
    // so editing the categories in config.toml also re-sorts past days.
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

    // [limits]: app_id = minutes
    function parseLimits(table) {
        const m = {}
        for (const k of Object.keys(table)) {
            const n = parseInt(table[k])
            if (n > 0)
                m[k] = n
        }
        limits = m
    }

    function parseTime(s) {
        const m = s.match(/^(\d{1,2}):(\d{2})$/)
        if (!m) return -1
        const h = parseInt(m[1]), mm = parseInt(m[2])
        return (h >= 0 && h <= 23 && mm >= 0 && mm <= 59) ? h * 60 + mm : -1
    }

    function parseDays(s) {
        const names = ["sun", "mon", "tue", "wed", "thu", "fri", "sat"]
        if (!s) return [0, 1, 2, 3, 4, 5, 6]
        const out = []
        for (const part of s.toLowerCase().split(",")) {
            const range = part.split("-")
            if (range.length === 2) {
                const a = names.indexOf(range[0]), b = names.indexOf(range[1])
                if (a >= 0 && b >= 0) {
                    for (let d = a; ; d = (d + 1) % 7) {
                        if (out.indexOf(d) < 0) out.push(d)
                        if (d === b) break
                    }
                }
            } else {
                const d = names.indexOf(part)
                if (d >= 0 && out.indexOf(d) < 0) out.push(d)
            }
        }
        return out
    }

    // [schedules]: target = ["HH:MM-HH:MM[,HH:MM-HH:MM] [days]", ...], one rule per string
    function parseSchedules(table) {
        const lines = []
        for (const target of Object.keys(table))
            for (const rule of [].concat(table[target]))
                lines.push(target + " " + rule)
        const m = {}
        for (const raw of lines) {
            const line = raw.replace(/#.*$/, "").trim()
            if (!line) continue
            const p = line.split(/\s+/)
            if (p.length < 2) continue

            const target = p[0]
            const windows = []
            for (const span of p[1].split(",")) {
                const bounds = span.split("-")
                if (bounds.length !== 2) continue
                const start = parseTime(bounds[0])
                const end = parseTime(bounds[1])
                if (start >= 0 && end >= 0 && start !== end)
                    windows.push({ start: start, end: end })
            }
            if (windows.length === 0) continue

            const days = parseDays(p[2] ?? "")
            m[target] = m[target] ?? []
            m[target].push({ windows: windows, days: days })
        }
        schedules = m
        enforce(lastWindows)
    }

    // "minutes N" sets how long a task needs (default 10); every other line is a
    // target, as in [schedules]. No table, or no targets, gates nothing.
    // [gate]: targets that stay closed while tasks are owed, and the minutes of grace
    function parseTaskGate(gate) {
        const targets = []
        for (const t of [].concat(gate.targets ?? []))
            if (typeof t === "string" && t.trim() !== "")
                targets.push(t.trim())
        let minutes = 10
        const n = parseInt(gate.minutes)
        if (n > 0 && n <= 240) minutes = n
        taskGateTargets = targets
        taskGateMinutes = minutes
        enforce(lastWindows)
    }

    Component.onCompleted: revision++

    IpcHandler {
        target: "usage"
        function toggle(): void { root.toggleWidget() }
        function toggleFocus(): void { root.toggleFocusWidget() }
    }

    Connections {
        target: Hyprland
        function onActiveToplevelChanged() { root.onFocusChanged() }
    }

    // once a second, so the focus counter ticks live; credit() only adds time
    // that has really passed, so a slow tick never over-counts. The window list
    // is re-read here too, so a window opened by a blocked app is closed promptly.
    Timer {
        interval: 1000
        repeat: true
        running: true
        onTriggered: {
            root.credit()
            root.refreshWindows()
            root.enforce(root.lastWindows)
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
        path: Quickshell.env("HOME") + "/.local/state/lumin/app-usage.json"
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

    // every table is read from config.toml whenever the file is read; a missing table is empty
    Connections {
        target: Config
        function onDataChanged() {
            const c = Config.data
            root.parseLimits(c.limits ?? {})
            root.parseSchedules(c.schedules ?? {})
            root.parseCategories(c.categories ?? {})
            root.parseTaskGate(c.gate ?? {})
            const apps = c.focus?.apps
            root.focusApps = Array.isArray(apps) ? apps : []
        }
    }
}
