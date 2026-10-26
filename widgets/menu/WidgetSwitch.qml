import QtQuick
import "../../services"

// The on/off pill a menu page uses to show or hide a desktop widget. The page
// decides what toggled does; the switch only shows the state.
Item {
    id: sw

    property string label: ""
    property bool checked: false
    signal toggled()

    implicitWidth: labelText.implicitWidth + 8 + pill.width
    implicitHeight: 18

    Text {
        id: labelText
        anchors.right: pill.left
        anchors.rightMargin: 8
        anchors.verticalCenter: parent.verticalCenter
        text: sw.label
        color: Qt.alpha(Theme.fg, 0.6)
        font.family: Theme.fontFamily
        font.pixelSize: 11
    }

    Rectangle {
        id: pill
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        width: 34
        height: 18
        radius: 9
        color: sw.checked ? Theme.accent : Qt.alpha(Theme.fg, 0.15)
        Behavior on color { ColorAnimation { duration: 150 } }

        Rectangle {
            x: sw.checked ? pill.width - width - 2 : 2
            anchors.verticalCenter: parent.verticalCenter
            width: 14
            height: 14
            radius: 7
            color: sw.checked ? Theme.bg : Qt.alpha(Theme.fg, 0.7)
            Behavior on x { NumberAnimation { duration: 150; easing.type: Easing.OutCubic } }
        }

        MouseArea {
            anchors.fill: parent
            cursorShape: Qt.PointingHandCursor
            onClicked: sw.toggled()
        }
    }
}
