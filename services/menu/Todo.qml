pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

// Todo data layer. One file per due date: todo-YYYY-MM-DD.txt, in the config
// directory. A file starts with a "# YYYY-MM-DD" header (the template) and
// holds lines like:
//   - [ ] Send the weekly update | due 2026-10-26 | p1 | id k3j9x
// The id makes each line addressable, so tasks with the same title are fine.
// Items are grouped for the panel by how far their due date is from today.
Singleton {
    id: root

    readonly property string dir: Quickshell.env("HOME") + "/.local/xdg/config"
    readonly property var groupLabels: ["Overdue", "Today", "Tomorrow", "This week", "This month", "Later"]
    readonly property var lineRe: /^- \[( |x)\] (.+?) \| due (\d{4}-\d{2}-\d{2})(?: \| p([1-3]))?(?: \| id ([a-z0-9]+))?$/

    property string today: ""
    // parsed items from every loaded file, in file then line order
    property var items: []
    // path -> FileView for each todo file known to the shell
    property var files: ({})

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
    function monthEnd(s) {
        const d = toDate(s)
        return dateStr(new Date(d.getFullYear(), d.getMonth() + 1, 0))
    }

    // 0 Overdue, 1 Today, 2 Tomorrow, 3 This week, 4 This month, 5 Later
    function groupOf(due) {
        if (due < today) return 0
        if (due === today) return 1
        if (due === addDays(today, 1)) return 2
        if (due <= addDays(today, 7)) return 3
        if (due <= monthEnd(today)) return 4
        return 5
    }

    function newId() {
        return Date.now().toString(36).slice(-4) + Math.floor(Math.random() * 1296).toString(36).padStart(2, "0")
    }

    function parseLine(line) {
        const m = line.match(lineRe)
        if (!m)
            return null
        return {
            done: m[1] === "x",
            title: m[2],
            due: m[3],
            priority: m[4] ? parseInt(m[4]) : 0,
            id: m[5] ?? ""
        }
    }

    function refreshToday() {
        today = dateStr(new Date())
    }

    function rebuild() {
        const list = []
        for (const p in files) {
            const m = p.match(/todo-(\d{4}-\d{2}-\d{2})\.txt$/)
            if (!m)
                continue
            const lines = files[p].text().split("\n")
            for (let i = 0; i < lines.length; i++) {
                const it = parseLine(lines[i])
                if (it) {
                    it.path = p
                    it.line = i
                    list.push(it)
                }
            }
        }
        items = list
    }

    function track(path) {
        const f = fileComp.createObject(root, { path: path })
        files[path] = f
        return f
    }

    // finds todo files on disk; starts tracking new ones and drops removed ones
    function scan() {
        lister.running = true
    }

    function reloadFile(path) {
        const f = files[path]
        if (f)
            f.reload()
    }

    Component {
        id: fileComp
        FileView {
            watchChanges: true
            onFileChanged: reload()
            onLoaded: root.rebuild()
            onLoadFailed: root.rebuild()
        }
    }

    Process {
        id: lister
        command: ["sh", "-c", "ls -1 \"$1\"/todo-*.txt 2>/dev/null", "sh", root.dir]
        stdout: StdioCollector {
            onStreamFinished: {
                const found = text.split("\n").filter(l => l !== "")
                for (const p of found)
                    if (!root.files[p])
                        root.track(p)
                for (const p in root.files)
                    if (found.indexOf(p) < 0) {
                        root.files[p].destroy()
                        delete root.files[p]
                    }
                root.rebuild()
            }
        }
    }

    // appends a line, creating the file with its template header if needed.
    // Appending in the shell means an existing file is never overwritten.
    Process {
        id: appender
        property string path: ""
        property string due: ""
        property string line: ""
        command: ["sh", "-c",
            "f=\"$1\"; if [ ! -e \"$f\" ]; then printf '# %s\\n' \"$2\" > \"$f\"; fi; printf '%s\\n' \"$3\" >> \"$f\"",
            "sh", path, due, line]
        onExited: root.scan()
    }

    // edits one line, found by its id, in a file. The change is made by awk
    // in the shell, so it's written straight to disk and doesn't depend on a
    // FileView's copy of the file. TO empty deletes the line.
    Process {
        id: editor
        property string path: ""
        command: ["sh", "-c", "true"]
        onExited: root.reloadFile(path)
    }

    function edit(item, to) {
        if (item.id === "" || editor.running)
            return
        editor.path = item.path
        editor.command = ["env", "TAG= | id " + item.id, "TO=" + to, "sh", "-c",
            "awk 'substr($0, length($0) - length(ENVIRON[\"TAG\"]) + 1) == ENVIRON[\"TAG\"] { if (ENVIRON[\"TO\"] != \"\") print ENVIRON[\"TO\"] substr($0, 6); next } { print }' \"$1\" > \"$1.tmp\" && mv \"$1.tmp\" \"$1\"",
            "sh", item.path]
        editor.running = true
    }

    function add(title, due, priority) {
        const clean = title.replace(/[\r\n]+/g, " ").replace(/\s*\|\s*/g, " / ").trim()
        if (clean === "")
            return
        const path = dir + "/todo-" + due + ".txt"
        appender.path = path
        appender.due = due
        appender.line = "- [ ] " + clean + " | due " + due
            + (priority ? " | p" + priority : "") + " | id " + newId()
        appender.running = true
    }

    function toggle(item) {
        edit(item, item.done ? "- [ ]" : "- [x]")
    }

    function remove(item) {
        edit(item, "")
    }

    // a minute tick catches a new day and new files; edits to known files arrive
    // through the FileView watch. Opening the menu rescans straight away.
    Timer {
        interval: 60000
        repeat: true
        running: true
        onTriggered: {
            root.refreshToday()
            root.rebuild()
            root.scan()
        }
    }

    Connections {
        target: MenuState
        function onOpenChanged() {
            if (MenuState.open)
                root.scan()
        }
    }

    Component.onCompleted: {
        refreshToday()
        scan()
    }
}
