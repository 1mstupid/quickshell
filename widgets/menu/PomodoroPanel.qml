import QtQuick
import "../../services"
import "../../services/menu"

// Pomodoro tab, as today's focus log: the day's focus time, then a grid with
// one row per hour and one cell per 5 minutes (darker = more focus). Pomodoro
// work time counts as focus even when no window has focus. The timer runs in
// a compact strip at the bottom. The switch shows or hides the focus widget.
Item {
    id: panel

    // the Loader in the menu sizes this panel
    anchors.fill: parent

    readonly property int step: 5
    readonly property var slots: AppUsage.focusSlots(AppUsage.dayKey(), AppUsage.revision)
    readonly property real totalSec: AppUsage.focusTotal(AppUsage.dayKey(), AppUsage.revision)

    function fmt(secs) {
        const m = Math.floor(secs / 60)
        const s = secs % 60
        return String(m).padStart(2, "0") + ":" + String(s).padStart(2, "0")
    }

    readonly property string readout: Pomodoro.done ? "00:00"
        : fmt(Pomodoro.active ? Pomodoro.remaining : Pomodoro.minutes * 60)

    Item {
        id: header
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.margins: 12
        height: 18

        Text {
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            text: "focus  " + AppUsage.fmtHms(panel.totalSec)
            color: Theme.fg
            font.family: Theme.fontFamilyAlt
            font.pixelSize: 13
            font.bold: true
        }

        WidgetSwitch {
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            label: "desktop"
            checked: AppUsage.focusWidgetShown
            onToggled: AppUsage.toggleFocusWidget()
        }
    }

    // 24 hour rows of twelve 5-minute cells; the label marks every sixth hour
    Column {
        id: grid
        anchors.top: header.bottom
        anchors.topMargin: 10
        anchors.left: parent.left
        anchors.leftMargin: 12
        width: parent.width - 24
        spacing: 1

        Repeater {
            model: 24

            Row {
                id: hourRow
                required property int index
                width: grid.width
                height: 4
                spacing: 1

                Text {
                    width: 16
                    height: parent.height
                    verticalAlignment: Text.AlignVCenter
                    text: hourRow.index % 6 === 0 ? String(hourRow.index).padStart(2, "0") : ""
                    color: Qt.alpha(Theme.fg, 0.4)
                    font.family: Theme.fontFamily
                    font.pixelSize: 7
                }

                Repeater {
                    model: 12

                    Rectangle {
                        required property int index
                        readonly property real sec: panel.slots[hourRow.index * 12 + index] ?? 0

                        width: (hourRow.width - 16 - 12) / 12
                        height: hourRow.height
                        radius: 1
                        // a full 5 minutes is the darkest cell
                        color: sec > 0
                            ? Qt.alpha(Theme.accent, 0.3 + 0.7 * Math.min(sec / 300, 1))
                            : Qt.alpha(Theme.fg, 0.07)
                    }
                }
            }
        }
    }

    // the pomodoro: readout, play or pause, stop, and duration while idle
    Row {
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: parent.bottom
        anchors.bottomMargin: 12
        height: 26
        spacing: 14

        Text {
            height: parent.height
            verticalAlignment: Text.AlignVCenter
            text: panel.readout
            color: Pomodoro.done ? Theme.red : Theme.fg
            font.family: Theme.fontFamilyAlt
            font.pixelSize: 16
            font.bold: true
        }

        Text {
            id: mainBtn
            height: parent.height
            verticalAlignment: Text.AlignVCenter
            text: Pomodoro.done ? "" : Pomodoro.running ? "󰏤" : "󰐊"
            visible: !Pomodoro.done
            color: mainMouse.containsMouse ? Theme.accent : Theme.fg
            font.family: Theme.fontFamily
            font.pixelSize: 18
            Behavior on color { ColorAnimation { duration: 120 } }

            MouseArea {
                id: mainMouse
                anchors.fill: parent
                anchors.margins: -6
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: {
                    if (Pomodoro.running)
                        Pomodoro.pause()
                    else if (Pomodoro.paused)
                        Pomodoro.resume()
                    else
                        Pomodoro.start()
                }
            }
        }

        Text {
            height: parent.height
            verticalAlignment: Text.AlignVCenter
            text: "󰓛"
            visible: Pomodoro.active || Pomodoro.done
            color: stopMouse.containsMouse ? Theme.alert : Qt.alpha(Theme.fg, 0.6)
            font.family: Theme.fontFamily
            font.pixelSize: 18
            Behavior on color { ColorAnimation { duration: 120 } }

            MouseArea {
                id: stopMouse
                anchors.fill: parent
                anchors.margins: -6
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: Pomodoro.stop()
            }
        }

        Text {
            id: minus
            readonly property bool allowed: !Pomodoro.active && Pomodoro.minutes > 1
            height: parent.height
            verticalAlignment: Text.AlignVCenter
            text: "−"
            color: !allowed ? Qt.alpha(Theme.fg, 0.2)
                 : minusMouse.containsMouse ? Theme.accent : Theme.fg
            font.family: Theme.fontFamilyAlt
            font.pixelSize: 16
            Behavior on color { ColorAnimation { duration: 120 } }

            MouseArea {
                id: minusMouse
                anchors.fill: parent
                anchors.margins: -6
                hoverEnabled: true
                cursorShape: minus.allowed ? Qt.PointingHandCursor : Qt.ArrowCursor
                onClicked: if (minus.allowed) Pomodoro.setMinutes(Pomodoro.minutes - panel.step)
            }
        }

        Text {
            height: parent.height
            verticalAlignment: Text.AlignVCenter
            text: Pomodoro.minutes + " min"
            color: Qt.alpha(Theme.fg, 0.6)
            font.family: Theme.fontFamilyAlt
            font.pixelSize: 11
        }

        Text {
            id: plus
            readonly property bool allowed: !Pomodoro.active && Pomodoro.minutes < 90
            height: parent.height
            verticalAlignment: Text.AlignVCenter
            text: "+"
            color: !allowed ? Qt.alpha(Theme.fg, 0.2)
                 : plusMouse.containsMouse ? Theme.accent : Theme.fg
            font.family: Theme.fontFamilyAlt
            font.pixelSize: 16
            Behavior on color { ColorAnimation { duration: 120 } }

            MouseArea {
                id: plusMouse
                anchors.fill: parent
                anchors.margins: -6
                hoverEnabled: true
                cursorShape: plus.allowed ? Qt.PointingHandCursor : Qt.ArrowCursor
                onClicked: if (plus.allowed) Pomodoro.setMinutes(Pomodoro.minutes + panel.step)
            }
        }
    }
}
