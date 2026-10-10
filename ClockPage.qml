import QtQuick
import Quickshell

// Dashboard page: large time and date. The bar's clock hides while the
// dashboard is open, so this takes its place.
Item {
    id: root

    SystemClock {
        id: clock
        precision: SystemClock.Minutes
    }

    Column {
        anchors.centerIn: parent
        spacing: 4

        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: Qt.formatDateTime(clock.date, "h:mm AP")
            font.family: Theme.fontFamily
            font.pixelSize: 40
            font.bold: true
            color: Theme.fg
        }

        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: Qt.formatDateTime(clock.date, "dddd, d MMMM").toUpperCase()
            font.family: Theme.fontFamily
            font.pixelSize: 10
            font.bold: true
            font.letterSpacing: 1.5
            color: Qt.alpha(Theme.accent, 0.8)
        }
    }
}
