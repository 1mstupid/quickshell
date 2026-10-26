import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import Quickshell.Services.Notifications
import "../../services"
import "../notch"

// One notch hung from the top-right corner, holding the stacked toasts.
// Hidden while there are no notifications.
PanelWindow {
    id: root

    readonly property int cardWidth: 350
    readonly property int pad: 10

    anchors { top: true; right: true }
    implicitWidth: notch.width
    implicitHeight: notch.height
    color: "transparent"
    exclusionMode: ExclusionMode.Ignore
    visible: Notifications.notifications.values.length > 0

    // only the notch takes clicks; the rest of the window passes them through
    mask: Region { item: notch }

    // flush with the top and right screen edges: only the left shoulder shows, and the bottom-right corner is square
    Notch {
        id: notch
        bodyWidth: root.cardWidth + 2 * root.pad
        bodyHeight: column.implicitHeight + 2 * root.pad
        leftShoulder: true
        rightShoulder: false
        bottomRightSquare: true
    }

    ColumnLayout {
        id: column
        x: notch.bodyX + root.pad
        y: root.pad
        width: root.cardWidth
        spacing: 8

        Repeater {

            model: Notifications.notifications

            delegate: Rectangle {
                id: card
                required property var modelData

                // how long a toast stays; the timer and the ring both use it
                readonly property int lifetime: 5000

                Timer {
                    running: card.modelData.urgency !== NotificationUrgency.Critical
                    interval: card.lifetime
                    onTriggered: card.modelData.dismiss()
                }


                Layout.fillWidth: true
                // sized to its content, so long bodies are not clipped
                implicitHeight: layout.implicitHeight + 20
                radius: 8
                color: Qt.alpha(Theme.fg, 0.06)
                border.width: modelData.urgency === NotificationUrgency.Critical ? 2 : 0
                border.color: Theme.fg
                RowLayout {
                    id: layout
                    anchors.fill: parent
                    anchors.margins: 10
                    spacing: 10

                    Image {
                        Layout.preferredHeight: 36
                        Layout.preferredWidth: 36
                        Layout.alignment: Qt.AlignTop
                        fillMode: Image.PreserveAspectFit
                        visible: source.toString() !== ""
                        // image is a path or URL; appIcon is a theme name, so it needs image://icon/
                        source: card.modelData.image !== ""
                            ? card.modelData.image
                            : (card.modelData.appIcon !== "" ? "image://icon/" + card.modelData.appIcon : "")
                    }
                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 2

                        Text {
                            Layout.fillWidth: true
                            text: card.modelData.summary
                            color: Theme.fg
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.fontSize + 2
                            font.bold: true
                            elide: Text.ElideRight
                        }
                        Text {
                            Layout.fillWidth: true
                            visible: text !== ""
                            text: card.modelData.body
                            color: Theme.fg
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.fontSize + 1
                            elide: Text.ElideRight
                            wrapMode: Text.WordWrap
                            maximumLineCount: 3
                        }
                    }
                }
                // an outline that drains around the toast as it times out,
                // like the Pomodoro ring; critical toasts never time out, so no ring
                Canvas {
                    id: ring
                    anchors.fill: parent
                    visible: card.modelData.urgency !== NotificationUrgency.Critical

                    // 1 = full outline, 0 = gone
                    property real frac: 1
                    onFracChanged: requestPaint()
                    onWidthChanged: requestPaint()
                    onHeightChanged: requestPaint()

                    NumberAnimation {
                        target: ring
                        property: "frac"
                        from: 1
                        to: 0
                        duration: card.lifetime
                        running: ring.visible
                    }

                    onPaint: {
                        const ctx = getContext("2d")
                        ctx.reset()
                        const inset = 1
                        const r = card.radius - inset
                        const x = inset, y = inset
                        const w = width - 2 * inset, h = height - 2 * inset
                        ctx.beginPath()
                        ctx.moveTo(x + r, y)
                        ctx.lineTo(x + w - r, y)
                        ctx.arcTo(x + w, y, x + w, y + r, r)
                        ctx.lineTo(x + w, y + h - r)
                        ctx.arcTo(x + w, y + h, x + w - r, y + h, r)
                        ctx.lineTo(x + r, y + h)
                        ctx.arcTo(x, y + h, x, y + h - r, r)
                        ctx.lineTo(x, y + r)
                        ctx.arcTo(x, y, x + r, y, r)
                        ctx.closePath()
                        // one dash as long as the perimeter fraction left, then a gap
                        const per = 2 * (w + h) - 8 * r + 2 * Math.PI * r
                        ctx.setLineDash([Math.max(0, frac) * per, per + 1])
                        ctx.lineWidth = 2
                        ctx.strokeStyle = String(Theme.accent)
                        ctx.stroke()
                    }
                }

                MouseArea {
                    anchors.fill: parent
                    onClicked: card.modelData.dismiss()
                }
            }
        }
    }
}
