import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import "../../services"

// Spike, off by default: `qs ipc call notchspike toggle`. Checks whether an
// Overlay window with an exclusive zone reserves the same strip at the top that
// the bar does, and whether it stays under nothing else it should not.
// Delete once the layer question is settled.
PanelWindow {
    id: root

    screen: PillState.originScreen
    visible: false

    anchors { top: true; left: true; right: true }
    implicitHeight: Theme.effectiveBarHeight
    exclusiveZone: visible ? Theme.effectiveBarHeight : 0
    exclusionMode: ExclusionMode.Normal

    color: "transparent"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.namespace: "quickshell-notchspike"

    // only the pill takes input, so the rest of the screen stays usable
    mask: Region { item: pill }

    IpcHandler {
        target: "notchspike"
        function toggle(): void { root.visible = !root.visible }
    }

    Rectangle {
        id: pill
        anchors.horizontalCenter: parent.horizontalCenter
        y: 0
        width: 180
        height: Theme.effectiveBarHeight
        color: Theme.bg
        radius: height / 2
        border.width: 1
        border.color: Qt.alpha(Theme.border, 0.6)

        Text {
            anchors.centerIn: parent
            text: "spike"
            color: Theme.fg
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSize
        }
    }
}
