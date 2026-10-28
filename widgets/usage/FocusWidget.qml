import QtQuick
import Quickshell
import Quickshell.Wayland
import "../../services"

// Today's focus time on the wallpaper layer, bottom-left, beside the usage ring.
// Drawn as the same card: the live total, and the study cycle below it, four
// dots that fill as work sessions finish, with the phase the timer is on.
// Hidden while the overview is open. Clicks pass through.
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

    // passing AppUsage.revision makes these re-evaluate when the numbers change
    readonly property real totalSec: AppUsage.focusTotal(AppUsage.dayKey(), AppUsage.revision)
    readonly property int pomos: AppUsage.pomodoros(AppUsage.dayKey(), AppUsage.revision)
    // four dots per cycle; the set shows full through the long break
    readonly property int setFilled: Pomodoro.phase === "long" ? 4 : pomos % 4
    readonly property string phaseLabel: Pomodoro.phase === "work" ? "work"
        : Pomodoro.phase === "short" ? "short break" : "long break"

    visible: AppUsage.focusWidgetShown && !Overview.open

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

            // the live total
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

            // the cycle: dots on the left, the phase on the right
            Item {
                width: col.width
                height: 12

                Row {
                    id: dots
                    anchors.left: parent.left
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 6

                    Repeater {
                        model: 4

                        Rectangle {
                            required property int index
                            width: 8
                            height: 8
                            radius: 4
                            color: index < root.setFilled ? Theme.accent : Qt.alpha(Theme.fg, 0.15)
                            Behavior on color { ColorAnimation { duration: 150 } }
                        }
                    }
                }

                Text {
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    text: root.phaseLabel
                    color: Qt.alpha(Theme.fg, 0.6)
                    font.family: Theme.fontFamilyAlt
                    font.pixelSize: 11
                }
            }
        }
    }
}
