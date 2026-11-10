import QtQuick
import "../../services"

// A glyph button for the layout bar: lit while its widget is on the wallpaper.
Item {
    id: btn

    property string glyph: ""
    property string label: ""
    property bool checked: false
    signal toggled()

    implicitWidth: 28
    implicitHeight: 28

    Accessible.role: Accessible.Button
    Accessible.name: btn.label

    Rectangle {
        anchors.fill: parent
        radius: 8
        color: btn.checked ? Qt.alpha(Theme.accent, 0.25)
             : Qt.alpha(Theme.fg, mouse.containsMouse ? 0.12 : 0.06)
        Behavior on color { ColorAnimation { duration: 120 } }
    }

    Text {
        anchors.centerIn: parent
        text: btn.glyph
        color: btn.checked ? Theme.accent : Qt.alpha(Theme.fg, 0.6)
        font.family: Theme.fontFamily
        font.pixelSize: 16
    }

    MouseArea {
        id: mouse
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: btn.toggled()
    }
}
