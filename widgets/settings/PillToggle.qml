import QtQuick
import "../../services"

// An on/off switch: a pill with a knob. It shows `checked` and says `toggled()` when it is
// clicked; the owner changes `checked`, so the value has one source and the switch never
// disagrees with it.
Rectangle {
    id: sw

    property bool checked: false
    signal toggled()

    implicitWidth: 36
    implicitHeight: 20
    radius: height / 2
    color: checked ? Theme.accent : Qt.alpha(Theme.fg, 0.15)
    Behavior on color { ColorAnimation { duration: 120 } }

    Rectangle {
        width: 14
        height: 14
        radius: 7
        y: 3
        x: sw.checked ? sw.width - width - 3 : 3
        color: sw.checked ? Theme.bg : Theme.fg
        Behavior on x { NumberAnimation { duration: 120; easing.type: Easing.OutCubic } }
        Behavior on color { ColorAnimation { duration: 120 } }
    }

    MouseArea {
        anchors.fill: parent
        cursorShape: Qt.PointingHandCursor
        onClicked: {
            Sounds.play("toggle")
            sw.toggled()
        }
    }
}
