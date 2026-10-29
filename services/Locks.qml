pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

// Caps Lock state, read from the kernel LED class. sysfs has no change
// events, so the file is polled.
Singleton {
    id: root

    property bool caps: false
    readonly property bool shown: caps
    readonly property string label: "CAPS LOCK"

    Process {
        id: probe
        command: ["sh", "-c", "cat /sys/class/leds/*::capslock/brightness 2>/dev/null"]
        stdout: StdioCollector {
            onStreamFinished: root.caps = text.split("\n").some(l => l.trim() === "1")
        }
    }

    Timer {
        interval: 500
        repeat: true
        running: true
        triggeredOnStart: true
        onTriggered: probe.running = true
    }
}
