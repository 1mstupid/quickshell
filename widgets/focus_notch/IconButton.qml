import QtQuick
import "../../services"

// A round icon button for the notch's strip: accent when it is the main action, grey otherwise.
Rectangle {
    id: btn

    property string glyph
    property bool main: false
    signal clicked()

    implicitWidth: 32
    implicitHeight: 32
    radius: width / 2
    color: main ? (mouse.containsMouse ? Qt.lighter(Theme.accent, 1.1) : Theme.accent)
                : (mouse.containsMouse ? Qt.alpha(Theme.fg, 0.2) : Qt.alpha(Theme.fg, 0.1))
    Behavior on color { ColorAnimation { duration: 120 } }

    Text {
        anchors.centerIn: parent
        text: btn.glyph
        color: btn.main ? Theme.bg : Theme.fg
        font.family: Theme.fontFamily
        font.pixelSize: 15
    }
    MouseArea {
        id: mouse
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: btn.clicked()
    }
}
