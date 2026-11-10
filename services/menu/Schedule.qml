pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import "ScheduleMd.js" as ScheduleMd

// The daily schedule: a fixed clock of blocks and a weekly grid of what goes in
// them, kept in schedule.md in the config directory and edited by hand. The
// format and the planning live in ScheduleMd.js:
//   | 05:00-07:30 | Bloco 1 | Emergência |      |   (Clock)
//   | Seg         | Mat 1   | Fis 1      |      |   (Week)
// Until there is a file the built-in template is used; Schedule.init() (or
// `qs ipc call schedule init`) writes it out to be edited. Today's blocks are
// not written to todo.md up front: they show in the task list as slots, and a
// slot becomes a task (Todo.materialize) when it is started or ticked, so a
// block that is skipped leaves nothing overdue behind.
Singleton {
    id: root

    readonly property string path: Quickshell.env("HOME") + "/.local/xdg/config/schedule.md"

    // the file's text; fromFile is false while it is missing and the template stands in
    property string fileText: ""
    property bool fromFile: false
    readonly property string source: fromFile ? fileText : ScheduleMd.defaultText()
    readonly property var parsed: ScheduleMd.parse(source)
    // what could not be read in the file, each with its line number
    readonly property var errors: parsed.errors

    // the minute clock moves the time of day on, so nothing has to poll
    readonly property int nowMin: clock.date.getHours() * 60 + clock.date.getMinutes()
    readonly property int weekday: clock.date.getDay()

    readonly property var plan: ScheduleMd.dayPlan(parsed, weekday)
    readonly property var slots: ScheduleMd.slots(plan)
    readonly property var week: ScheduleMd.weekView(parsed)

    // the row of the plan that is on now (a break counts), or null
    readonly property var current: ScheduleMd.blockAt(plan, nowMin)
    // the title of the planned block that is on now, or "". These two are
    // strings, so what depends on them only updates when a block changes and
    // not on every minute.
    readonly property string currentTitle: {
        const s = slots.find(x => x.start <= nowMin && nowMin < x.end)
        return s !== undefined ? s.title : ""
    }
    readonly property string pastKey: slots.filter(s => s.end <= nowMin).map(s => s.title).join("\n")

    // what is left to do: todo.md's tasks and the slots that have no task yet
    readonly property var agenda: ScheduleMd.agenda(Todo.upcoming, Todo.items, slots, Todo.today,
                                                     pastKey === "" ? [] : pastKey.split("\n"))

    function fmt(min) {
        return ScheduleMd.fmtTime(min)
    }

    // minutes planned for the block with this title today, or 0
    function minutesFor(title) {
        const s = slots.find(x => x.title === title)
        return s !== undefined ? s.minutes : 0
    }

    // writes the built-in template to schedule.md, unless the file is there. The
    // shell's noclobber (set -C) makes the write fail when the file exists, so an
    // edit in progress can never be overwritten.
    function init() {
        if (fromFile)
            return
        Quickshell.execDetached(["sh", "-c", "set -C; printf '%s\\n' \"$1\" > \"$2\"",
                                 "sh", ScheduleMd.defaultText(), root.path])
        reloadTimer.restart()
    }

    Timer {
        id: reloadTimer
        interval: 300
        onTriggered: file.reload()
    }

    SystemClock {
        id: clock
        precision: SystemClock.Minutes
    }

    FileView {
        id: file
        path: root.path
        watchChanges: true
        onFileChanged: reload()
        onLoaded: {
            root.fileText = text()
            root.fromFile = true
        }
        onLoadFailed: {
            root.fileText = ""
            root.fromFile = false
        }
    }

    IpcHandler {
        target: "schedule"
        function init(): void { root.init() }
    }
}
