import QtQuick
import Quickshell
import Quickshell.Io

Item {
    id: root

    // Set by the bar to its screen name, e.g. "HDMI-A-1"
    property string outputName: ""

    property string raw: ""
    readonly property string current: parse(raw)

    implicitWidth: label.implicitWidth
    implicitHeight: label.implicitHeight

    // Focused lines look like: "* HDMI-A-1: 2 [scrolling] (focused)"
    function parse(text) {
        for (const line of text.split("\n")) {
            const m = line.match(/^\*\s+(\S+?):\s*(\S+)/)
            if (m && m[1] === outputName)
                return m[2]
        }
        return ""
    }

    Process {
        id: proc
        command: ["umbriel", "workspaces"]
        stdout: StdioCollector {
            id: collector
            onStreamFinished: root.raw = collector.text
        }
    }

    // Poll. Skips a tick if the previous call is still running.
    Timer {
        interval: 300
        running: true
        repeat: true
        triggeredOnStart: true
        onTriggered: if (!proc.running) proc.running = true
    }

    Text {
        id: label
        anchors.centerIn: parent
        text: root.current
        color: Theme.fg
        font.pixelSize: 14
    }
}
