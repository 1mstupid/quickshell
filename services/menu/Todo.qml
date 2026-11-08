pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import "TodoMd.js" as TodoMd

// Todo data layer, kept in todo.md in the config directory and edited by hand.
// The format and the parsing live in TodoMd.js:
//   ## 2026-11-04
//   - [ ] Send the weekly update
// The widget only ticks and deletes; it rewrites that one line of the file.
Singleton {
    id: root

    readonly property string path: Quickshell.env("HOME") + "/.local/xdg/config/todo.md"

    // parsed tasks, in file order; empty while the file is missing
    property var items: []
    // true once the file has been read (or found missing), so an empty list means empty
    property bool loaded: false

    // the minute clock rolls this over at midnight, so nothing has to poll
    readonly property string today: Qt.formatDate(clock.date, "yyyy-MM-dd")

    // open tasks due today or overdue, in the order to do them
    readonly property var upcoming: TodoMd.upcoming(items, today)

    function toDate(s) {
        const p = s.split("-").map(Number)
        return new Date(p[0], p[1] - 1, p[2])
    }
    function addDays(s, n) {
        const d = toDate(s)
        d.setDate(d.getDate() + n)
        return Qt.formatDate(d, "yyyy-MM-dd")
    }

    // `to` is the replacement line, or null to delete it. A line that no longer
    // matches what was parsed is left alone; the file watch refreshes the list.
    // The list is updated here too, so a tick shows without waiting for the watch.
    function edit(item, to) {
        const next = TodoMd.edit(file.text(), item.line, item.raw, to)
        if (next === null)
            return
        file.setText(next)
        items = TodoMd.parse(next)
    }

    function toggle(item) {
        edit(item, TodoMd.toggled(item.raw))
    }

    // adds tracked minutes to the task's ~ token, and ticks it when `finish` is set
    function addSpent(item, minutes, finish) {
        let raw = item.raw
        if (minutes > 0)
            raw = TodoMd.withSpent(raw, item.spent + minutes)
        if (finish && !item.done)
            raw = TodoMd.toggled(raw)
        if (raw !== item.raw)
            edit(item, raw)
    }

    // the task with this date and title, an open one in preference to a ticked one
    function find(due, title) {
        return items.find(t => t.due === due && t.title === title && !t.done)
            ?? items.find(t => t.due === due && t.title === title) ?? null
    }

    function remove(item) {
        edit(item, null)
    }

    SystemClock {
        id: clock
        precision: SystemClock.Minutes
    }

    FileView {
        id: file
        path: root.path
        atomicWrites: true
        watchChanges: true
        onFileChanged: reload()
        onLoaded: {
            root.items = TodoMd.parse(text())
            root.loaded = true
        }
        onLoadFailed: {
            root.items = []
            root.loaded = true
        }
    }
}
