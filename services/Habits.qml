pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

// Habit data layer, kept in habits.json in the config directory:
//   {
//     "day": "2026-10-24",            the day the statuses below refer to
//     "habits": [{"id": "0", "name": "Read", "status": "completed"}],
//     "history": {"2026-10-23": ["0"]} ids completed on each earlier day
//   }
// At the first load or tick after midnight, the previous day's completed ids
// move into "history" and every status goes back to "pending".
Singleton {
    id: root

    readonly property string path: Quickshell.env("HOME") + "/.local/xdg/config/habits.json"
    readonly property int weeks: 5

    property var data: ({ day: "", habits: [], history: {} })

    function dateStr(d) { return Qt.formatDate(d, "yyyy-MM-dd") }
    function toDate(s) {
        const p = s.split("-").map(Number)
        return new Date(p[0], p[1] - 1, p[2])
    }
    function addDays(s, n) {
        const d = toDate(s)
        d.setDate(d.getDate() + n)
        return dateStr(d)
    }

    // whether habit `id` was completed on `date` (a day string)
    function doneOn(id, date) {
        if (date === data.day) {
            const h = data.habits.find(x => x.id === id)
            return !!h && h.status === "completed"
        }
        const ids = data.history[date]
        return !!ids && ids.indexOf(id) >= 0
    }

    // consecutive completed days ending today, or ending yesterday while today is still pending
    function streak(id) {
        let d = data.day
        if (!doneOn(id, d))
            d = addDays(d, -1)
        let n = 0
        while (doneOn(id, d)) {
            n++
            d = addDays(d, -1)
        }
        return n
    }

    // weeks * 7 day strings, oldest first, one column per week starting on Sunday.
    // Days after today are included so the grid stays rectangular; the panel leaves them empty.
    function gridDates() {
        const today = data.day
        const sunday = addDays(today, -toDate(today).getDay() - 7 * (weeks - 1))
        const out = []
        for (let i = 0; i < weeks * 7; i++)
            out.push(addDays(sunday, i))
        return out
    }

    function load(text) {
        let d = null
        try {
            d = JSON.parse(text)
        } catch (e) {
            d = null
        }
        // anything that isn't the expected shape is treated as an empty file
        data = (d && Array.isArray(d.habits))
            ? Object.assign({ day: "", history: {} }, d)
            : { day: "", habits: [], history: {} }
        rollover()
    }

    function rollover() {
        const now = dateStr(new Date())
        if (data.day === now)
            return
        const history = Object.assign({}, data.history)
        if (data.day !== "")
            history[data.day] = data.habits.filter(h => h.status === "completed").map(h => h.id)
        const habits = data.habits.map(h => ({ id: h.id, name: h.name, status: "pending" }))
        data = { day: now, habits: habits, history: history }
        save()
    }

    function save() {
        store.setText(JSON.stringify(data, null, 2) + "\n")
    }

    function toggle(id) {
        const habits = data.habits.map(h => h.id === id
            ? { id: h.id, name: h.name, status: h.status === "completed" ? "pending" : "completed" }
            : h)
        data = Object.assign({}, data, { habits: habits })
        save()
    }

    FileView {
        id: store
        path: root.path
        atomicWrites: true
        watchChanges: true
        onFileChanged: reload()
        onLoaded: root.load(text())
        // no file yet: start empty and create it on the first save
        onLoadFailed: root.load("")
    }

    Timer {
        interval: 60000
        repeat: true
        running: true
        onTriggered: root.rollover()
    }
}
