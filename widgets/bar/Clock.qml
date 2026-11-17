import QtQuick
import Quickshell
import "../../services"

Item {
    id: root

    implicitWidth: row.implicitWidth + 16
    implicitHeight: 15
    onXChanged: updatePillState()
    onYChanged: updatePillState()
    Component.onCompleted: updatePillState()

    function updatePillState() {
        // Map this item's center or top-left to global coordinates
        let globalPos = mapToItem(null, 0, 0) 
        PillState.clockX = globalPos.x + (width / 2)
        PillState.clockY = globalPos.y + (height / 2)
    }

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
            text: Qt.formatDateTime(clock.date, UserSettings.clockFormat)
            font.family: Theme.fontFamilyAlt
            font.pixelSize: 15
            font.bold: true
            color: Theme.fg
        }
    }
}
