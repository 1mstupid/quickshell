import QtQuick
import Quickshell
import Quickshell.Wayland
import "../../services"

// Today's app time on the wallpaper layer: above the wallpaper, below every
// window. Shows the total and the three most used apps. Clicks pass through.
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
    implicitWidth: 200
    implicitHeight: col.implicitHeight

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

    Column {
        id: col
        width: parent.width
        spacing: 6

        Text {
            text: "today  " + AppUsage.fmt(root.totalSec)
            color: Qt.alpha(Theme.fg, 0.6)
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSize
        }

        Repeater {
            model: root.rows

            Item {
                id: line
                required property var modelData
                width: col.width
                height: 18

                Text {
                    anchors.left: parent.left
                    anchors.right: time.left
                    anchors.rightMargin: 8
                    anchors.verticalCenter: parent.verticalCenter
                    text: line.modelData.app
                    color: Qt.alpha(Theme.fg, 0.8)
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontSize - 1
                    elide: Text.ElideRight
                }
                Text {
                    id: time
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    text: AppUsage.fmt(line.modelData.sec)
                    color: Qt.alpha(Theme.fg, 0.5)
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontSize - 1
                }
                Rectangle {
                    anchors.left: parent.left
                    anchors.bottom: parent.bottom
                    height: 2
                    radius: 1
                    color: Qt.alpha(Theme.accent, 0.7)
                    width: parent.width * (line.modelData.sec / root.topSec)
                }
            }
        }
    }
}
