
import QtQuick
import Quickshell
import Quickshell.Hyprland
import QtQuick.Layouts
import QtQuick.Effects
import "../../services"

// Compact row of vertical workspace capsules.
// Always shows the first five workspaces, including empty ones.
RowLayout {
    id: root

    property string outputName: ""
    property int maxVisible: 5

    spacing: 5

    Wm {
        id: wm
        outputName: root.outputName
    }

    Repeater {
        // Generate fixed workspace indicators independently of
        // Hyprland's list, which may omit empty workspaces.
        model: Array.from({ length: root.maxVisible }, (_, i) => {
            const id = i + 1
            const ws = wm.workspaces.find(w => w.id === id)

            return {
                id: id,
                index: id,
                focused: ws ? ws.focused : false,
                occupied: ws ? ws.occupied : false
            }
        })

        Rectangle {
            id: workspaceIndicator

            required property var modelData

            readonly property bool focused: modelData.focused
            readonly property bool occupied: modelData.occupied
            property real glowOpacity: focused ? 0.85 : 0.0

            Layout.alignment: Qt.AlignVCenter

            implicitWidth: focused ? 8 : 4
            implicitHeight: focused ? 16 : 10
            radius: focused ? 4 : 2

            color: focused
                ? Theme.accent
                : occupied
                    ? Qt.alpha(Theme.accent, 0.6)
                    : Qt.alpha(Theme.fg, 0.22)

            layer.enabled: workspaceIndicator.focused
            layer.smooth: workspaceIndicator.focused

            layer.effect: MultiEffect {
                shadowEnabled: workspaceIndicator.focused
                shadowBlur: 1.0
                shadowScale: 1.25
                shadowOpacity: workspaceIndicator.focused ? 0.85 : 0.0

                shadowColor: Qt.rgba(
                    Theme.accent.r,
                    Theme.accent.g,
                    Theme.accent.b,
                    0.85
                )
            }

            Behavior on implicitWidth {
                NumberAnimation {
                    duration: 200
                    easing.type: Easing.OutCubic
                }
            }

            Behavior on implicitHeight {
                NumberAnimation {
                    duration: 200
                    easing.type: Easing.OutCubic
                }
            }

            Behavior on color {
                ColorAnimation { duration: 150 }
            }

            Behavior on glowOpacity {
                NumberAnimation {
                    duration: 180
                    easing.type: Easing.OutCubic
                }
            }

            MouseArea {
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor

                onClicked: Hyprland.dispatch(
                    'hl.dsp.focus({ workspace = "' + modelData.id + '" })'
                )
            }
        }
    }
}

