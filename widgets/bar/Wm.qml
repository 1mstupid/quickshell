import QtQuick
import Quickshell
import Quickshell.Io
import "../../services"

// Workspaces for one output, pushed by `umbriel subscribe workspaces`.
// No polling: one long-lived process, restarted if it exits.
Item {
    id: root

    property string outputName: ""
    property var workspaces: []

    function apply(line) {
        let msg
        try {
            msg = JSON.parse(line)
        } catch (e) {
            return
        }
        if (msg.event !== "workspaces")
            return
        workspaces = msg.data
            .filter(w => w.output === outputName)
            .sort((a, b) => a.index - b.index)
    }

    Process {
        id: sub
        command: ["/nix/store/yj9f18sd6gj5qyv1q2zwgc97iiab94pf-umbriel-0.1.0/bin/umbriel", "subscribe", "workspaces"]
        running: true
        stdout: SplitParser {
            onRead: line => root.apply(line)
        }
        onExited: restart.restart()
    }

    Timer {
        id: restart
        interval: 1000
        onTriggered: sub.running = true
    }
}
