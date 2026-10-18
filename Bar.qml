import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import "./services"

PanelWindow {
    id: root

    property var modelData
    screen: modelData

    // toggled by: qs ipc call bar toggle
    property bool shown: true
    IpcHandler {
        target: "bar"
        function toggle(): void { root.shown = !root.shown }
    }

    anchors { top: true; left: true; right: true }

    WlrLayershell.layer: WlrLayer.Top

    readonly property real topGap: 8

    implicitHeight: topGap + pill.height

    // hidden bar gives its space back to windows
    exclusiveZone: shown ? topGap + Theme.effectiveBarHeight : 0

    color: "transparent"
    visible: Theme.barStateReady && shown

    mask: Region { item: pill }

    Recorder {
        id: recorder
    }

    Rectangle {
        id: pill

        readonly property int pad: Math.round(12 * Theme.barScale)
        readonly property int recWidth: recRow.implicitWidth + pad

        // reserve the same space on both sides so the clock stays centered
        readonly property int side: recorder.recording ? recWidth : 0

        y: root.topGap
        anchors.horizontalCenter: parent.horizontalCenter
        width: clock.implicitWidth + 2 * (pad + side)
        height: Theme.effectiveBarHeight
        radius: height / 2

        color: Qt.alpha(Theme.bg, 0.92)
        border.width: 1
        border.color: Qt.alpha(Theme.border, 0.6)

        Behavior on width {
            NumberAnimation { duration: 200; easing.type: Easing.OutCubic }
        }

        // left side, only while wf-recorder runs; click stops it
        RowLayout {
            id: recRow
            anchors.verticalCenter: parent.verticalCenter
            anchors.left: parent.left
            anchors.leftMargin: pill.pad
            spacing: 5
            opacity: recorder.recording ? 1 : 0

            Behavior on opacity {
                NumberAnimation { duration: 150; easing.type: Easing.OutQuad }
            }

            Rectangle {
                Layout.alignment: Qt.AlignVCenter
                implicitWidth: 6
                implicitHeight: 6
                radius: 3
                color: Theme.red

                SequentialAnimation on opacity {
                    running: recorder.recording
                    loops: Animation.Infinite
                    NumberAnimation { to: 0.2; duration: 600 }
                    NumberAnimation { to: 1; duration: 600 }
                }
            }

            Text {
                Layout.alignment: Qt.AlignVCenter
                text: recorder.fmt(recorder.elapsed)
                font.family: Theme.fontFamilyAlt
                font.pixelSize: 12
                font.bold: true
                color: Theme.red
            }

            MouseArea {
                Layout.fillWidth: true
                Layout.fillHeight: true
                cursorShape: Qt.PointingHandCursor
                onClicked: recorder.stop()
            }
        }

        Clock {
            id: clock
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.verticalCenter: parent.verticalCenter
        }
    }
}
