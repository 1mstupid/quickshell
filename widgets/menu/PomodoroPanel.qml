import QtQuick
import "../../services"
import "../../services/menu"

// Pomodoro tab: the time left (or the set duration while idle), a thin
// progress line, the controls and the duration. The duration can be changed
// only while idle; the state is kept by the Pomodoro service.
Item {
    id: panel

    // the Loader in the menu sizes this panel
    anchors.fill: parent

    readonly property int step: 5

    function fmt(secs) {
        const m = Math.floor(secs / 60)
        const s = secs % 60
        return String(m).padStart(2, "0") + ":" + String(s).padStart(2, "0")
    }

    readonly property string readout: Pomodoro.done ? "00:00"
        : fmt(Pomodoro.active ? Pomodoro.remaining : Pomodoro.minutes * 60)

    readonly property string status: Pomodoro.done ? "time's up"
        : Pomodoro.running ? "focus"
        : Pomodoro.paused ? "paused"
        : "ready"

    Column {
        anchors.centerIn: parent
        spacing: 12

        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: panel.readout
            color: Pomodoro.done ? Theme.red : Theme.fg
            font.family: Theme.fontFamilyAlt
            font.pixelSize: 30
            font.bold: true
        }

        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: panel.status
            color: Qt.alpha(Theme.fg, 0.5)
            font.family: Theme.fontFamily
            font.pixelSize: 11
        }

        // progress line, same look as the media seek bar
        Rectangle {
            anchors.horizontalCenter: parent.horizontalCenter
            width: 220
            height: 4
            radius: 2
            color: Qt.alpha(Theme.fg, 0.12)

            Rectangle {
                width: parent.width * Pomodoro.fraction
                height: parent.height
                radius: parent.radius
                color: Pomodoro.paused ? Theme.disabled : Theme.accent
                Behavior on width { NumberAnimation { duration: 200; easing.type: Easing.OutCubic } }
            }
        }

        // controls: play / pause / resume, and stop while a timer is in progress
        Row {
            anchors.horizontalCenter: parent.horizontalCenter
            spacing: 18

            Text {
                id: mainBtn
                readonly property bool isPlaying: Pomodoro.running
                text: Pomodoro.done ? "" : isPlaying ? "󰏤" : "󰐊"
                visible: !Pomodoro.done
                color: mainMouse.containsMouse ? Theme.accent : Theme.fg
                font.family: Theme.fontFamily
                font.pixelSize: 26
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
                text: "󰓛"
                visible: Pomodoro.active || Pomodoro.done
                color: stopMouse.containsMouse ? Theme.alert : Qt.alpha(Theme.fg, 0.6)
                font.family: Theme.fontFamily
                font.pixelSize: 26
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
        }

        // duration: − and + while idle, otherwise just the value
        Row {
            anchors.horizontalCenter: parent.horizontalCenter
            spacing: 10

            Text {
                id: minus
                readonly property bool allowed: !Pomodoro.active && Pomodoro.minutes > 1
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
                text: Pomodoro.minutes + " min"
                color: Qt.alpha(Theme.fg, 0.6)
                font.family: Theme.fontFamilyAlt
                font.pixelSize: 11
            }
            Text {
                id: plus
                readonly property bool allowed: !Pomodoro.active && Pomodoro.minutes < 90
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
}
