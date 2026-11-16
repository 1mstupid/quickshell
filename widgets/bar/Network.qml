import QtQuick
import Quickshell.Io
import "../../services"

Item {
    id: root

    property string state: "disconnected" // "wifi", "ethernet", "disconnected"
    property int strength: 0

    implicitWidth: state === "ethernet" ? 14 : 15
    implicitHeight: 12

    onStateChanged: wifiCanvas.requestPaint()
    onStrengthChanged: wifiCanvas.requestPaint()

    Process {
        id: netProc
        command: ["sh", "-c", "nmcli -t -f TYPE,STATE,SIGNAL dev wifi list --rescan no 2>/dev/null | grep ':activated:' || nmcli -t -f TYPE,STATE dev | grep ':connected'"]
        stdout: SplitParser {
            onRead: data => {
                const line = data.trim()
                if (line.startsWith("802-3-ethernet") || line.startsWith("ethernet")) {
                    root.state = "ethernet"
                    root.strength = 100
                } else if (line.includes(":activated:") || line.startsWith("802-11-wireless")) {
                    root.state = "wifi"
                    const parts = line.split(":")
                    root.strength = parts.length >= 3 ? (parseInt(parts[2]) || 0) : 75
                } else {
                    root.state = "disconnected"
                    root.strength = 0
                }
            }
        }
    }

    Timer {
        interval: 5000
        running: root.visible
        repeat: true
        triggeredOnStart: true
        onTriggered: {
            root.state = "disconnected"
            netProc.running = true
        }
    }

    // Wi-Fi fan: bottom dot + 3 rounded-cap arcs (matches right icon in reference)
    Canvas {
        id: wifiCanvas
        anchors.fill: parent
        visible: root.state !== "ethernet"

        readonly property color activeColor: Theme.fg
        readonly property color dimColor: Qt.alpha(Theme.fg, 0.22)
        onActiveColorChanged: requestPaint()

        onPaint: {
            const ctx = getContext("2d")
            ctx.reset()
            ctx.lineCap = "round"
            ctx.lineWidth = 1.65

            const cx = width / 2
            const cy = height - 1.8
            const startAngle = -Math.PI * 0.76
            const endAngle = -Math.PI * 0.24

            // Bottom center dot (level 1: > 0%)
            ctx.fillStyle = String(root.state === "wifi" && root.strength > 0 ? activeColor : dimColor)
            ctx.beginPath()
            ctx.arc(cx, cy, 1.35, 0, Math.PI * 2)
            ctx.fill()

            // 3 concentric rounded arcs (levels 2, 3, 4)
            const radii = [4.0, 6.7, 9.4]
            const thresholds = [25, 50, 75]

            for (let i = 0; i < 3; i++) {
                const on = root.state === "wifi" && root.strength >= thresholds[i]
                ctx.strokeStyle = String(on ? activeColor : dimColor)
                ctx.beginPath()
                ctx.arc(cx, cy, radii[i], startAngle, endAngle)
                ctx.stroke()
            }
        }
    }

    // Ethernet: 4 pill-capped ascending bars (matches left icon in reference)
    Row {
        anchors.bottom: parent.bottom
        anchors.bottomMargin: 0.5
        anchors.horizontalCenter: parent.horizontalCenter
        spacing: 1.5
        visible: root.state === "ethernet"

        Repeater {
            model: 4
            Rectangle {
                required property int index
                anchors.bottom: parent.bottom
                width: 2.3
                height: 2.5 + index * 2.7 // starts as a dot, grows into tall pills
                radius: width / 2
                color: Theme.accent
            }
        }
    }
}
