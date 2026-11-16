import QtQuick
import "../../services"

// A small diamond: the bouncing marker, the beads of a gap, and the bits of a burst.
Item {
    id: dot

    property real size: 8
    property bool lit: false
    property color litColor: Theme.primary
    property color offColor: Qt.alpha(Theme.fg, 0.3)
    property color lineColor: Theme.border

    width: dot.size
    height: dot.size

    Rectangle {
        anchors.centerIn: parent
        width: dot.size * 0.72
        height: width
        rotation: 45
        antialiasing: true
        color: dot.lit ? dot.litColor : dot.offColor
        border.width: 1
        border.color: dot.lit ? dot.litColor : dot.lineColor
    }
}
