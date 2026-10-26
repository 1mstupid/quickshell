import QtQuick
import Quickshell
import Quickshell.Wayland
import "../../services"

// Today's focus time on the wallpaper layer, bottom-left, so it sits beside the
// app widget. Drawn as the bar pill's card: the total and one bar per hour,
// full at an hour of focus. Hidden while the overview is open. Clicks pass through.
PanelWindow {
    id: root

    screen: PillState.originScreen
    anchors {
        left: true
        bottom: true
    }
    margins {
        left: Theme.edgeInset
        bottom: Theme.edgeInset
    }
    implicitWidth: 240
    implicitHeight: card.height

    exclusionMode: ExclusionMode.Ignore
    color: "transparent"
    WlrLayershell.layer: WlrLayer.Background
    WlrLayershell.namespace: "quickshell-focus"
    mask: Region {}

    // passing AppUsage.revision makes this re-evaluate when the numbers change
    readonly property var slots: AppUsage.focusSlots(AppUsage.dayKey(), AppUsage.revision)
    readonly property real totalSec: AppUsage.focusTotal(AppUsage.dayKey(), AppUsage.revision)

    // focus seconds in one hour, from its twelve 5-minute slots
    function hourSec(h) {
        let s = 0
        for (let i = 0; i < 12; i++)
            s += root.slots[h * 12 + i] ?? 0
        return s
    }

    visible: AppUsage.focusWidgetShown && !Overview.open && totalSec > 0

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
                    text: "focus"
                    color: Theme.accent
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontSize + 1
                    font.bold: true
                }
                Text {
                    text: AppUsage.fmtHms(root.totalSec)
                    color: Theme.fg
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontSize + 1
                    font.bold: true
                }
            }

            // one bar per hour, midnight on the left
            Item {
                id: strip
                width: col.width
                height: 40

                Rectangle {
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.bottom: parent.bottom
                    height: 1
                    color: Qt.alpha(Theme.fg, 0.15)
                }

                Repeater {
                    model: 24

                    Rectangle {
                        required property int index
                        readonly property real sec: root.hourSec(index)

                        x: index * (width + 2)
                        width: (strip.width - 23 * 2) / 24
                        height: 40 * Math.min(sec / 3600, 1)
                        anchors.bottom: parent.bottom
                        radius: 1
                        color: Theme.accent
                    }
                }
            }
        }
    }
}
