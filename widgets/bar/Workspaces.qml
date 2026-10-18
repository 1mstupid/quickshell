import QtQuick
import Quickshell
import QtQuick.Layouts
import "../../services"

// Row of dots for one output. The focused dot grows and takes the accent.
RowLayout {
    id: root

    property string outputName: ""

    spacing: 6

    Wm {
        id: wm
        outputName: root.outputName
    }

    Repeater {
        model: wm.workspaces.filter(w => w.focused || w.occupied)

        Rectangle {
            required property var modelData
            readonly property bool focused: modelData.focused

            Layout.alignment: Qt.AlignVCenter
            implicitWidth: focused ? 16 : 6
            implicitHeight: 6
            radius: 3
            color: focused ? Theme.accent : Qt.alpha(Theme.accent, 0.45)

            Behavior on implicitWidth {
                NumberAnimation { duration: 200; easing.type: Easing.OutCubic }
            }
            Behavior on color { ColorAnimation { duration: 150 } }

            MouseArea {
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                onClicked: Quickshell.execDetached(["umbriel", "msg",
                    "workspace-switch:" + modelData.name + "/" + root.outputName])            }
        }
    }
}
