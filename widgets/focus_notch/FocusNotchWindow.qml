import QtQuick
import Quickshell
import Quickshell.Wayland
import "../../services"

// The focus strip's own window, sized to its open panel, so a compositor blur behind it covers
// the panel and not the whole screen. It is unmapped while the strip is closed.
PanelWindow {
    id: root

    // the open panel and the notch's shoulders on either side of it, and the band under it
    readonly property int panelW: 600
    readonly property int panelH: 600
    readonly property var strip: loader.item

    screen: PillState.originScreen
    anchors { top: true; left: true }
    margins.left: Math.round(((PillState.originScreen ? PillState.originScreen.width : 0) - panelW) / 2)
    implicitWidth: panelW
    implicitHeight: panelH

    color: "transparent"
    exclusionMode: ExclusionMode.Ignore
    visible: strip?.visible ?? false
    WlrLayershell.layer: WlrLayer.Top
    WlrLayershell.namespace: "qs-strip"
    // the keys go to the strip while it is up, as they did from the bar
    WlrLayershell.keyboardFocus: visible ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None
    // only the card takes clicks while the strip is hovered or open, so the rest passes through
    mask: Region { item: root.strip ? root.strip.maskItem : null }

    Loader {
        id: loader
        anchors.fill: parent
        sourceComponent: FocusNotch {}
    }
}
