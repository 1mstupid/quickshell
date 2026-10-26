pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

// Clipboard history, read from cliphist. Entries are stored by a
// `wl-paste --watch cliphist store` that the compositor starts once per
// session, so restarting the shell never starts a second watcher.
Singleton {
    id: root

    property bool open: false
    // one item per line of `cliphist list`: { id, preview, line }
    property var entries: []

    function toggle() { open = !open }
    function show()   { open = true }
    function hide()   { open = false }

    function reload() { listProc.running = true }

    // cliphist decodes from the whole list line, so the line is passed as an
    // argument and never interpolated into the shell command
    function copy(entry) {
        Quickshell.execDetached(["sh", "-c",
            "printf '%s\\n' \"$1\" | cliphist decode | wl-copy", "sh", entry.line])
    }

    function remove(entry) {
        Quickshell.execDetached(["sh", "-c",
            "printf '%s\\n' \"$1\" | cliphist delete", "sh", entry.line])
        entries = entries.filter(e => e !== entry)
    }

    Process {
        id: listProc
        command: ["cliphist", "list"]
        stdout: StdioCollector {
            onStreamFinished: {
                const out = []
                for (const line of text.split("\n")) {
                    const tab = line.indexOf("\t")
                    if (tab < 0)
                        continue
                    const preview = line.slice(tab + 1)
                    // images and other binary entries would paste as garbage text
                    if (preview.indexOf("[[ binary") === 0)
                        continue
                    out.push({ id: line.slice(0, tab), preview: preview, line: line })
                }
                root.entries = out
            }
        }
    }
}
