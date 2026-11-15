pragma Singleton
import QtQuick
import Quickshell

// Shared state for the bar pill and the morphing panels (wallpaper and colorscheme pickers,
// app launcher, control panel). The bar fades its pill from `progress` while a panel owns
// it, and the owning panel grows out of the origin pill.
QtObject {
    id: root

    // which panel owns the pill: "", "wallpapers", "colorschemes", "applauncher", "clipboard" or "focus"
    property string owner: ""
    readonly property bool active: owner !== ""

    // how long a panel takes to grow out of the pill, and to go back: the same for all of them
    readonly property int morphMs: 320

    // morph progress of the owning panel, 0 = pill, 1 = full panel
    property real progress: 0

    // the screen the morphing panels live on (first screen for now)
    readonly property var originScreen: Quickshell.screens.length > 0 ? Quickshell.screens[0] : null
    readonly property string originName: originScreen ? originScreen.name : ""

    // pill geometry, written by the origin bar through Bindings
    property real pillTop: 8
    property real pillWidth: 120
    property real pillHeight: 30
}
