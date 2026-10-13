import QtQuick
import QtQuick.Layouts
import Quickshell.Wayland
import Quickshell

PanelWindow {
    id: root

    property var modelData
    screen: modelData
    WlrLayershell.layer: WlrLayer.Top


    anchors {
        top: true
        left: true
    }

    margins {
        top: 8
    }
    readonly property real topGap: 8

    implicitWidth: tag.width
    implicitHeight: tag.height + topGap

    exclusiveZone: topGap + tag.collapsedHeight

    color: "transparent"
    visible: Theme.barStateReady

    mask: Region { item: tag }

    Item {
        id: tag

        readonly property real collapsedWidth: 40
        readonly property real collapsedHeight: Theme.effectiveBarHeight
        width: collapsedWidth
        height: collapsedHeight

        x: 0
        y: 0
        z: 0
        
        Behavior on height {

        }

        Behavior on width {
            NumberAnimation { duration: 260; easing.type: Easing.OutCubic }
        }

        Rectangle {
            anchors.fill: parent
            radius: root.expanded ? 18 : Math.min(width, height) / 2 - 5
            color: Qt.alpha(Theme.bg, 0.92)
            border.color: Qt.alpha(Theme.accent, 0.6)
            border.width: 1

            Behavior on radius {
                NumberAnimation { duration: 260; easing.type: Easing.OutCubic }
            }
        }
        RowLayout {
            id: tags

            anchors {
                top: parent.top
                left: parent.left
                right: parent.right
                bottom: parent.bottom
                topMargin: 5
                leftMargin: 10
                rightMargin: 10
                bottomMargin: 5
            }
            height: 10
            spacing: 10

            Wm {
                outputName: root.screen.name
                Layout.alignment: Qt.AlignHCenter | Qt.AlignVCenter
                Layout.fillWidth: true
                Layout.fillHeight: true
            }
        }
    }
}
