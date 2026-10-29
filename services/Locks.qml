pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

// Caps Lock and Num Lock state, read from the kernel LED classes. sysfs has no
// change events, so the files are polled.
Singleton {
    id: root

    property bool caps: false
    property bool num: false
    readonly property bool shown: caps || num
    readonly property string label: [caps ? "CAPS LOCK" : "", num ? "NUM LOCK" : ""]
        .filter(s => s !== "").join("   ")

    Process {
        id: probe
        command: ["sh", "-c",
            "for f in /sys/class/leds/*::capslock/brightness; do echo caps $(cat \"$f\"); done; "
            + "for f in /sys/class/leds/*::numlock/brightness; do echo num $(cat \"$f\"); done"]
        stdout: StdioCollector {
            onStreamFinished: {
                let c = false
                let n = false
                for (const line of text.split("\n")) {
                    const p = line.trim().split(/\s+/)
                    if (p[1] !== "1")
                        continue
                    if (p[0] === "caps") c = true
                    else if (p[0] === "num") n = true
                }
                root.caps = c
                root.num = n
            }
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
