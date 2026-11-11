import QtQuick

Item {
    id: root

    property alias text: label.text
    property alias color: label.color
    property alias font: label.font
    
    // Duration in milliseconds for the scroll animation, or set based on your preference
    property int scrollDuration: 3000 
    property bool triggerReset: false

    implicitHeight: label.implicitHeight
    clip: true

    readonly property real overflow: Math.max(0, label.implicitWidth - root.width)

    Text {
        id: label
        width: implicitWidth
        height: root.height
        verticalAlignment: Text.AlignVCenter
        x: 0
    }

    Binding {
        target: label
        property: "x"
        value: Math.max(0, (root.width - label.implicitWidth) / 2)
        when: root.overflow <= 0
    }

    // Reset position when triggerReset changes or text changes
    onTriggerResetChanged: {
        anim.restart()
    }
    onTextChanged: {
        anim.restart()
    }

    SequentialAnimation {
        id: anim
        running: root.overflow > 0
        loops: Animation.Infinite

        PauseAnimation { duration: 800 }
        NumberAnimation {
            target: label
            property: "x"
            to: -root.overflow
            duration: root.scrollDuration
        }
        PauseAnimation { duration: 1500 }
        NumberAnimation {
            target: label
            property: "x"
            to: 0
            duration: 0
        }
    }
}
