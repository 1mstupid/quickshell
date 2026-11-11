import QtQuick
import "../../services"

// Four small bars that dance while a track plays and rest where they are when it is paused.
Item {
    id: eq

    property bool playing: false
    property color tint: Theme.accent

    implicitWidth: row.implicitWidth
    implicitHeight: 14

    Row {
        id: row
        height: eq.implicitHeight
        spacing: 2

        Repeater {
            model: 4

            Rectangle {
                id: bar
                required property int index
                y: (parent.height - height) / 2
                width: 3
                height: 4
                radius: 1.5
                color: eq.tint

                // each bar gets its own tempo so they do not move in step
                SequentialAnimation on height {
                    running: eq.playing
                    loops: Animation.Infinite
                    NumberAnimation { to: 13; duration: 260 + bar.index * 70; easing.type: Easing.InOutSine }
                    NumberAnimation { to: 4; duration: 260 + bar.index * 70; easing.type: Easing.InOutSine }
                }
            }
        }
    }
}
