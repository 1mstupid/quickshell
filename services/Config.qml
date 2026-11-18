pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

// The hand-edited config, ~/.config/lumin/config.toml, one table per kind of setting.
// config.py reads and writes it (python3's tomllib, run with -I). `data` is the parsed
// file as plain objects: {} until the first read finishes and when the file is missing
// or broken, so every setting keeps its default. Changes to the file are read again, and
// `set` writes one value and reads it back.
Singleton {
    id: root

    readonly property string path: Quickshell.env("HOME") + "/.config/lumin/config.toml"
    readonly property string script: Quickshell.shellDir + "/services/config.py"

    property var data: ({})

    // reads and writes go one at a time: a write queued during a read waits for it,
    // and a change that lands during a read is read again afterwards
    property var pending: []
    property bool again: false

    function read() {
        if (reader.running) {
            again = true
            return
        }
        reader.running = true
    }

    // one value of one table; JSON-encoded so numbers, booleans, strings and lists all work
    function set(table, key, value) {
        pending = pending.concat([[table, key, JSON.stringify(value)]])
        pump()
    }

    function pump() {
        if (writer.running || pending.length === 0)
            return
        const w = pending[0]
        pending = pending.slice(1)
        writer.command = ["python3", "-I", script, "set", path, w[0], w[1], w[2]]
        writer.running = true
    }

    Component.onCompleted: {
        // FileView will not create the folder on write, and the state files live beside it
        Quickshell.execDetached(["mkdir", "-p", Quickshell.env("HOME") + "/.local/state/lumin"])
        read()
    }

    Process {
        id: reader
        command: ["python3", "-I", root.script, "read", root.path]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    root.data = JSON.parse(text)
                } catch (e) {
                    root.data = ({})
                }
            }
        }
        onExited: {
            if (root.again) {
                root.again = false
                reader.running = true
            }
        }
    }

    Process {
        id: writer
        onExited: (code, status) => {
            // a write that worked is read back now, in case the watch below misses the rename
            if (code === 0)
                root.read()
            root.pump()
        }
    }

    FileView {
        path: root.path
        watchChanges: true
        onFileChanged: root.read()
    }
}
