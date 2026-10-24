import QtQuick
import Quickshell
import Quickshell.Wayland
import "../../services"

// Thin rounded frame around one screen, in the bar's background colour.
// Hidden while the overview is open. Clicks pass through.
PanelWindow {
    id: root

    property var modelData
    screen: modelData

    anchors {
        top: true
        bottom: true
        left: true
        right: true
    }
    exclusionMode: ExclusionMode.Ignore
    color: "transparent"
    WlrLayershell.layer: WlrLayer.Top
    WlrLayershell.namespace: "quickshell-border"
    visible: !Overview.open
    mask: Region {}

    Rectangle {
        anchors.fill: parent
        color: "transparent"
        border.width: 2
        border.color: Theme.bg
        radius: 12
    }
}
