import QtQuick
import Quickshell
import Quickshell.Wayland
import "../../services"

// The pomodoro on the wallpaper, bottom-left, beside the usage ring. Shows the
// session time with − and + to change it while idle, the four cycle dots, the
// phase, and the start, pause and stop buttons. Hidden while the overview is
// open. Only the card takes pointer events.
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
    mask: Region { item: card }

    // passing AppUsage.revision makes this re-evaluate when the numbers change
    readonly property int pomos: AppUsage.pomodoros(AppUsage.dayKey(), AppUsage.revision)
    // four dots per cycle; the set shows full through the long break
    readonly property int setFilled: Pomodoro.phase === "long" ? 4 : pomos % 4
    readonly property string phaseLabel: Pomodoro.phase === "work" ? "FOCUS"
        : Pomodoro.phase === "short" ? "SHORT BREAK" : "LONG BREAK"

    function fmt(secs) {
        const m = Math.floor(secs / 60)
        const s = secs % 60
        return String(m).padStart(2, "0") + ":" + String(s).padStart(2, "0")
    }

    readonly property string readout: Pomodoro.done ? "00:00"
        : fmt(Pomodoro.active ? Pomodoro.remaining : Pomodoro.minutes * 60)

    visible: AppUsage.focusWidgetShown && !Overview.open

    Rectangle {
        id: card

        readonly property int pad: 16

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
            spacing: 12

            // − time + ; the time is the big figure, like a timer face
            Row {
                anchors.horizontalCenter: parent.horizontalCenter
                spacing: 14

                Text {
                    id: minus
                    readonly property bool allowed: !Pomodoro.active && Pomodoro.minutes > 5
                    anchors.verticalCenter: parent.verticalCenter
                    text: "−"
                    color: !allowed ? Qt.alpha(Theme.fg, 0.2)
                         : minusMouse.containsMouse ? Theme.accent : Theme.fg
                    font.family: Theme.fontFamilyAlt
                    font.pixelSize: 18
                    Behavior on color { ColorAnimation { duration: 120 } }

                    MouseArea {
                        id: minusMouse
                        anchors.fill: parent
                        anchors.margins: -8
                        hoverEnabled: true
                        cursorShape: minus.allowed ? Qt.PointingHandCursor : Qt.ArrowCursor
                        onClicked: if (minus.allowed) Pomodoro.adjust(-5)
                    }
                }

                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: root.readout
                    color: Pomodoro.done ? Theme.red : Theme.fg
                    font.family: Theme.fontFamilyAlt
                    font.pixelSize: 34
                    font.bold: true
                }

                Text {
                    id: plus
                    readonly property bool allowed: !Pomodoro.active && Pomodoro.minutes < 90
                    anchors.verticalCenter: parent.verticalCenter
                    text: "+"
                    color: !allowed ? Qt.alpha(Theme.fg, 0.2)
                         : plusMouse.containsMouse ? Theme.accent : Theme.fg
                    font.family: Theme.fontFamilyAlt
                    font.pixelSize: 18
                    Behavior on color { ColorAnimation { duration: 120 } }

                    MouseArea {
                        id: plusMouse
                        anchors.fill: parent
                        anchors.margins: -8
                        hoverEnabled: true
                        cursorShape: plus.allowed ? Qt.PointingHandCursor : Qt.ArrowCursor
                        onClicked: if (plus.allowed) Pomodoro.adjust(5)
                    }
                }
            }

            // the cycle: four dots, filled as work sessions finish
            Row {
                anchors.horizontalCenter: parent.horizontalCenter
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
                anchors.horizontalCenter: parent.horizontalCenter
                text: root.phaseLabel
                color: Qt.alpha(Theme.fg, 0.5)
                font.family: Theme.fontFamilyAlt
                font.pixelSize: 10
                font.letterSpacing: 1
            }

            // start, pause or resume; stop appears while a session is on
            Row {
                anchors.horizontalCenter: parent.horizontalCenter
                spacing: 8

                Rectangle {
                    id: mainBtn
                    width: 104
                    height: 32
                    radius: 16
                    color: mainMouse.containsMouse ? Qt.lighter(Theme.accent, 1.1) : Theme.accent
                    Behavior on color { ColorAnimation { duration: 120 } }

                    Text {
                        anchors.centerIn: parent
                        text: Pomodoro.running ? "PAUSE" : Pomodoro.paused ? "RESUME" : "START"
                        color: Theme.bg
                        font.family: Theme.fontFamily
                        font.pixelSize: 12
                        font.bold: true
                    }
                    MouseArea {
                        id: mainMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: Pomodoro.toggle()
                    }
                }

                Rectangle {
                    visible: Pomodoro.active || Pomodoro.done
                    width: 64
                    height: 32
                    radius: 16
                    color: stopMouse.containsMouse ? Qt.alpha(Theme.alert, 0.25) : Qt.alpha(Theme.fg, 0.1)
                    Behavior on color { ColorAnimation { duration: 120 } }

                    Text {
                        anchors.centerIn: parent
                        text: "STOP"
                        color: Theme.fg
                        font.family: Theme.fontFamily
                        font.pixelSize: 12
                        font.bold: true
                    }
                    MouseArea {
                        id: stopMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: Pomodoro.stop()
                    }
                }
            }
        }
    }
}
