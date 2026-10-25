import QtQuick
import Quickshell
import Quickshell.Wayland
import "../../services"

// Today's app time on the wallpaper layer: above the wallpaper, below every
// window. Drawn as the bar pill's card, so it reads as part of the bar.
// Shows the total and the three most used apps. Clicks pass through.
PanelWindow {
    id: root

    screen: PillState.originScreen
    anchors {
        right: true
        bottom: true
    }
    margins {
        right: Theme.edgeInset
        bottom: Theme.edgeInset
    }
    implicitWidth: 240
    implicitHeight: card.height

    exclusionMode: ExclusionMode.Ignore
    color: "transparent"
    WlrLayershell.layer: WlrLayer.Background
    WlrLayershell.namespace: "quickshell-usage"
    mask: Region {}

    // passing AppUsage.revision makes this re-evaluate when the numbers change
    readonly property var allRows: AppUsage.totals(AppUsage.dayKey(), AppUsage.revision)
    readonly property var rows: allRows.slice(0, 3)
    readonly property real topSec: rows.length > 0 ? rows[0].sec : 1
    readonly property real totalSec: allRows.reduce((s, r) => s + r.sec, 0)

    visible: allRows.length > 0

    Rectangle {
        id: card

        readonly property int pad: 14

        width: root.width
        height: col.implicitHeight + 2 * pad
        radius: 12
        color: Qt.alpha(Theme.bg, 0.92)
        border.width: 1
        border.color: Qt.alpha(Theme.border, 0.6)

        Column {
            id: col
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.margins: card.pad
            spacing: 10

            Row {
                spacing: 8

                Text {
                    text: "today"
                    color: Theme.accent
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontSize + 1
                    font.bold: true
                }
                Text {
                    text: AppUsage.fmt(root.totalSec)
                    color: Theme.fg
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontSize + 1
                    font.bold: true
                }
            }

            Repeater {
                model: root.rows

                Item {
                    id: line
                    required property var modelData
                    width: col.width
                    height: 36

                    Text {
                        id: name
                        anchors.left: parent.left
                        anchors.right: time.left
                        anchors.rightMargin: 10
                        anchors.top: parent.top
                        text: line.modelData.app
                        color: Theme.fg
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fontSize + 1
                        elide: Text.ElideRight
                    }
                    Text {
                        id: time
                        anchors.right: parent.right
                        anchors.top: parent.top
                        text: AppUsage.fmt(line.modelData.sec)
                        color: Theme.fg
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fontSize + 1
                    }
                    Rectangle {
                        anchors.left: parent.left
                        anchors.bottom: parent.bottom
                        height: 3
                        radius: 2
                        color: Theme.accent
                        width: parent.width * (line.modelData.sec / root.topSec)
                    }
                }
            }
        }
    }
}
