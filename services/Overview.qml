pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

// Overview state from `umbriel subscribe overview`. One shared process,
// since the event is global rather than per output.
Singleton {
    id: root

    property bool open: false

    Process {
        id: sub
        command: ["umbriel", "subscribe", "overview"]
        running: true
        stdout: SplitParser {
            onRead: line => {
                let msg
                try {
                    msg = JSON.parse(line)
                } catch (e) {
                    return
                }
                if (msg.event === "overview")
                    root.open = msg.data.open === true
            }
        }
        onExited: restart.restart()
    }

    Timer {
        id: restart
        interval: 1000
        onTriggered: sub.running = true
    }
}
