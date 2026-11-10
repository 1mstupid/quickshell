import QtQuick
import "../../services"

// A pill button for the notch: accent when it is the main action, grey otherwise.
Rectangle {
    id: btn

    property string label
    property bool main: false
    signal clicked()

    implicitWidth: caption.implicitWidth + 24
    implicitHeight: 28
    radius: height / 2
    color: main ? (mouse.containsMouse ? Qt.lighter(Theme.accent, 1.1) : Theme.accent)
                : (mouse.containsMouse ? Qt.alpha(Theme.fg, 0.2) : Qt.alpha(Theme.fg, 0.1))
    Behavior on color { ColorAnimation { duration: 120 } }

    Text {
        id: caption
        anchors.centerIn: parent
        text: btn.label
        color: btn.main ? Theme.bg : Theme.fg
        font.family: Theme.fontFamily
        font.pixelSize: 11
        font.bold: true
    }
    MouseArea {
        id: mouse
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: btn.clicked()
    }
}
