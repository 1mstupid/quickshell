import QtQuick
import "../../services"

// A pill button for the notch: accent when it is the main action, grey otherwise,
// with an optional icon before the label.
Rectangle {
    id: btn

    property string label
    property string glyph: ""
    property bool main: false
    signal clicked()

    implicitWidth: content.implicitWidth + 24
    implicitHeight: 28
    radius: height / 2
    color: main ? (mouse.containsMouse ? Qt.lighter(Theme.accent, 1.1) : Theme.accent)
                : (mouse.containsMouse ? Qt.alpha(Theme.fg, 0.2) : Qt.alpha(Theme.fg, 0.1))
    Behavior on color { ColorAnimation { duration: 120 } }

    Row {
        id: content
        anchors.centerIn: parent
        spacing: 6

        Text {
            anchors.verticalCenter: parent.verticalCenter
            visible: btn.glyph !== ""
            text: btn.glyph
            color: btn.main ? Theme.bg : Theme.fg
            font.family: Theme.fontFamily
            font.pixelSize: 12
        }
        Text {
            anchors.verticalCenter: parent.verticalCenter
            text: btn.label
            color: btn.main ? Theme.bg : Theme.fg
            font.family: Theme.fontFamilySans
            font.pixelSize: 12
            font.weight: Font.DemiBold
        }
    }
    MouseArea {
        id: mouse
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: btn.clicked()
    }
}
