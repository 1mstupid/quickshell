import QtQuick
import Quickshell.Services.UPower
import "../../services"

Row {
    id: root
    spacing: 4

    // Set to false if you want only the battery icon with no text
    property bool showPercentage: true

    readonly property var dev: UPower.displayDevice
    readonly property bool hasBattery: dev && dev.isLaptopBattery
    readonly property int pct: hasBattery ? Math.round(dev.percentage * 100) : 0
    readonly property bool charging: hasBattery && (
        dev.state === UPowerDeviceState.Charging ||
        dev.state === UPowerDeviceState.FullyCharged
    )
    readonly property bool low: hasBattery && !charging && pct <= 20
    readonly property color fillColor: low ? Theme.red : (charging ? Theme.accent : Theme.fg)

    // Collapses to 0 width on desktops without a battery
    visible: hasBattery

    // Drawn battery body + terminal cap (matches center icon in reference)
    Row {
        anchors.verticalCenter: parent.verticalCenter
        spacing: 1

        Rectangle {
            anchors.verticalCenter: parent.verticalCenter
            width: 19
            height: 11
            radius: 3.5
            color: "transparent"
            border.width: 1.3
            border.color: root.low ? Theme.red : Qt.alpha(Theme.fg, 0.75)

            // Inner rounded fill block with clear gap from border
            Rectangle {
                anchors.left: parent.left
                anchors.top: parent.top
                anchors.bottom: parent.bottom
                anchors.margins: 2.2
                width: Math.max(2.5, (parent.width - 4.4) * (root.pct / 100))
                radius: 1.8
                color: root.fillColor

                Behavior on width { NumberAnimation { duration: 200; easing.type: Easing.OutCubic } }
                Behavior on color { ColorAnimation { duration: 150 } }
            }
        }

        // Rounded right-side terminal nub
        Canvas {
            anchors.verticalCenter: parent.verticalCenter
            width: 2
            height: 5

            readonly property color nubColor: root.low ? Theme.red : Qt.alpha(Theme.fg, 0.75)
            onNubColorChanged: requestPaint()

            onPaint: {
                const ctx = getContext("2d")
                ctx.reset()
                ctx.fillStyle = String(nubColor)
                // Half-pill rounded only on the right side
                ctx.beginPath()
                ctx.moveTo(0, 0)
                ctx.lineTo(0.5, 0)
                ctx.arc(0.5, height / 2, height / 2, -Math.PI / 2, Math.PI / 2)
                ctx.lineTo(0, height)
                ctx.closePath()
                ctx.fill()
            }
        }
    }

    Text {
        visible: root.showPercentage
        anchors.verticalCenter: parent.verticalCenter
        text: root.pct + "%"
        font.family: Theme.fontFamilyAlt
        font.pixelSize: 11
        font.bold: true
        color: root.low ? Theme.red : (root.charging ? Theme.accent : Theme.fg)
    }
}
