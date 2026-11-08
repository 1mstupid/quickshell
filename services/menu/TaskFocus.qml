pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

// The task timer: one task from todo.md in focus at a time, with the time spent
// on it counted up. Pausing keeps the task in focus; stopping or finishing banks
// the time into the task's ~ token in todo.md (see TodoMd.js) and clears the
// focus. Finishing also ticks the task. Focusing another task banks the current
// one first.
//
// The task is found by its date and title, not its line, so edits to the file by
// hand do not lose it. The state file holds "due<TAB>title<TAB>startMs<TAB>accMs",
// so a focus survives a shell restart. If the task is ticked by hand, or removed
// from the file, the focus ends; a ticked one still gets its time banked.
Singleton {
    id: root

    readonly property string stateFile: Quickshell.env("HOME") + "/.local/xdg/config/task-focus"

    property string due: ""
    property string title: ""
    property double startMs: 0    // set while running
    property double accMs: 0      // time banked before the current run
    property double now: Date.now()

    readonly property bool active: title !== ""
    readonly property bool running: startMs > 0
    readonly property bool paused: active && !running
    readonly property double elapsedMs: accMs + (running ? Math.max(0, now - startMs) : 0)

    // the task in focus, while it is still open in the file
    readonly property var item: {
        if (!active)
            return null
        const t = Todo.find(due, title)
        return t !== null && !t.done ? t : null
    }

    function sameTask(task) {
        return active && task.due === due && task.title === title
    }

    function persist() {
        store.setText(due + "\t" + title + "\t" + Math.round(startMs) + "\t" + Math.round(accMs) + "\n")
    }

    function clear() {
        due = ""
        title = ""
        startMs = 0
        accMs = 0
        persist()
    }

    // puts a task in focus and starts counting; the one in focus is banked first
    function focus(task) {
        if (sameTask(task)) {
            resume()
            return
        }
        if (active)
            commit(false)
        due = task.due
        title = task.title.replace(/\t/g, " ")
        accMs = 0
        now = Date.now()
        startMs = now
        persist()
    }

    function pause() {
        if (!running)
            return
        accMs = elapsedMs
        startMs = 0
        persist()
    }

    function resume() {
        if (!paused)
            return
        now = Date.now()
        startMs = now
        persist()
    }

    function toggle() {
        if (running)
            pause()
        else
            resume()
    }

    // banks the elapsed time, rounded to the minute, and ends the focus. The
    // state is cleared before the file is written, because the write makes the
    // list change, which the check below listens to.
    function commit(finish) {
        const t = Todo.find(due, title)
        const minutes = Math.round(elapsedMs / 60000)
        clear()
        if (t !== null)
            Todo.addSpent(t, minutes, finish)
    }

    function stop() {
        if (active)
            commit(false)
    }

    // ends the focus and ticks the task
    function complete() {
        if (active)
            commit(true)
    }

    Timer {
        interval: 1000
        repeat: true
        running: root.running
        onTriggered: root.now = Date.now()
    }

    // the task was ticked or removed in the file
    Connections {
        target: Todo
        function onItemsChanged() {
            if (!root.active || !Todo.loaded)
                return
            const t = Todo.find(root.due, root.title)
            if (t === null)
                root.clear()
            else if (t.done)
                root.commit(false)
        }
    }

    FileView {
        id: store
        path: root.stateFile
        atomicWrites: true
        onLoaded: {
            const p = text().replace(/\n$/, "").split("\t")
            if (p.length < 4 || p[1] === "")
                return
            root.due = p[0]
            root.title = p[1]
            root.startMs = parseFloat(p[2]) || 0
            root.accMs = parseFloat(p[3]) || 0
            root.now = Date.now()
        }
    }

    IpcHandler {
        target: "taskfocus"
        function toggle(): void { root.toggle() }
        function stop(): void { root.stop() }
        function done(): void { root.complete() }
    }
}
