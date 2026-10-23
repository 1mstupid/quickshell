import QtQuick

// Single line of text that scrolls when it is wider than its box. It pauses
// at both ends and snaps back to the start when the text fits again.
Item {
    id: root

    property alias text: label.text
    property alias color: label.color
    property alias font: label.font

    implicitHeight: label.implicitHeight
    clip: true

    readonly property real overflow: Math.max(0, label.implicitWidth - root.width)

    Text {
        id: label
        width: implicitWidth
        height: root.height
        verticalAlignment: Text.AlignVCenter
    }

    Binding {
        target: label
        property: "x"
        value: 0
        when: root.overflow <= 0
    }

    SequentialAnimation {
        running: root.overflow > 0
        loops: Animation.Infinite

        PauseAnimation { duration: 1400 }
        NumberAnimation {
            target: label
            property: "x"
            to: -root.overflow
            duration: root.overflow * 35
        }
        PauseAnimation { duration: 1400 }
        NumberAnimation {
            target: label
            property: "x"
            to: 0
            duration: 0
        }
    }
}
