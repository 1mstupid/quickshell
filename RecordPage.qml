import QtQuick

// Dashboard page: record button, elapsed time, and a short status line.
// Takes the Recorder as `recorder` so it doesn't depend on id scope.
Item {
    id: root

    required property var recorder
    readonly property color red: "#e5484d"

    implicitHeight: col.implicitHeight

    Column {
        id: col
        anchors.horizontalCenter: parent.horizontalCenter
        spacing: 10

        Rectangle {
            id: btn
            anchors.horizontalCenter: parent.horizontalCenter
            width: 52
            height: 52
            radius: 26
            color: "transparent"
            border.color: root.red
            border.width: 2

            // red dot when idle, red square (stop icon) while recording
            Rectangle {
                anchors.centerIn: parent
                width: root.recorder.recording ? 16 : 22
                height: width
                radius: root.recorder.recording ? 3 : width / 2
                color: root.red

                Behavior on width { NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }
                Behavior on radius { NumberAnimation { duration: 160 } }
            }

            MouseArea {
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                onClicked: root.recorder.toggle()
            }
        }

        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: root.recorder.recording ? root.recorder.fmt(root.recorder.elapsed) : "Ready"
            font.family: Theme.fontFamily
            font.pixelSize: 22
            font.bold: true
            color: Theme.fg
        }

        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: root.recorder.recording ? "Click to stop" : "Click to record screen + audio"
            font.family: Theme.fontFamily
            font.pixelSize: 10
            color: Qt.alpha(Theme.fg, 0.5)
        }

        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: "Saves to ~/Videos/recordings"
            font.family: Theme.fontFamily
            font.pixelSize: 9
            color: Qt.alpha(Theme.accent, 0.6)
        }
    }
}
