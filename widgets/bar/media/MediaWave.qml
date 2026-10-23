import QtQuick
import "../../../services"

// Bar indicator for media: five bars that stay while a track is loaded and
// freeze when it is paused. Gone once the player is stopped or absent.
// Left click opens the media widget, right click stops the player.
Item {
    id: root

    implicitWidth: row.implicitWidth
    implicitHeight: 14

    MediaState { id: media }

    opacity: media.present ? 1 : 0
    visible: opacity > 0
    Behavior on opacity {
        NumberAnimation { duration: 150; easing.type: Easing.OutQuad }
    }

    Row {
        id: row
        height: root.implicitHeight
        spacing: 2

        Repeater {
            model: 5

            Rectangle {
                id: bar
                required property int index
                y: (parent.height - height) / 2
                width: 2
                height: 4
                radius: 1
                color: Theme.fg

                // each bar gets its own tempo so the wave does not move in step;
                // pausing stops the loop where it is
                SequentialAnimation on height {
                    running: media.playing
                    loops: Animation.Infinite
                    NumberAnimation { to: 13; duration: 280 + bar.index * 60; easing.type: Easing.InOutSine }
                    NumberAnimation { to: 4; duration: 280 + bar.index * 60; easing.type: Easing.InOutSine }
                }
            }
        }
    }

    MouseArea {
        anchors.fill: parent
        cursorShape: Qt.PointingHandCursor
        acceptedButtons: Qt.LeftButton | Qt.RightButton
        onClicked: m => {
            if (m.button === Qt.RightButton)
                media.kill()
            else
                MediaWidgetState.toggle()
        }
    }
}
