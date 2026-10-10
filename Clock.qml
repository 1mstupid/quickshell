import QtQuick
import Quickshell

Item {
    id: root

    signal toggleDashboard()

    implicitWidth: row.implicitWidth + 16
    implicitHeight: 15

    SystemClock {
        id: clock
        precision: SystemClock.Seconds
    }

    // Hover pill behind the content
    Rectangle {
        anchors.fill: parent
        radius: height / 2
        color: Qt.alpha(Theme.accent, 0)
        Behavior on color { ColorAnimation { duration: 150 } }
    }

    Row {
        id: row
        anchors.centerIn: parent
        spacing: 5

        // Hour and minute
        Text {
            id: timeText
            anchors.verticalCenter: parent.verticalCenter
            text: Qt.formatDateTime(clock.date, "h:mm AP")
            font.family: Theme.font
            font.pixelSize: 15
            font.bold: true
            color: Theme.fg
        }
    }

    MouseArea {
        id: mouse
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: root.toggleDashboard()
    }
}
