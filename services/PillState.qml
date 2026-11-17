pragma Singleton
import QtQuick
import Quickshell

// Shared state for the bar pill and the morphing panels (wallpaper and colorscheme pickers,
// app launcher, control panel, lockscreen). The bar fades its pill from `progress` while a panel
// owns it, and the owning panel grows out of the origin pill.
QtObject {
    id: root

    // which panel owns the pill: "", "wallpapers", "colorschemes", "applauncher", "clipboard", "focus", or "lock"
    property string owner: ""
    readonly property bool active: owner !== ""

    // how long a panel takes to grow out of the pill, and to go back: the same for all of them
    readonly property int morphMs: 320

    // The card a panel gave up when another panel took the pill. The next panel grows out of
    // it instead of out of the pill, so the two hand over without a pill-sized step. Cleared
    // once nothing owns the pill, so a stale card never starts a later panel.
    property real takeoverW: 0
    property real takeoverH: 0
    onOwnerChanged: if (owner === "") { takeoverW = 0; takeoverH = 0 }

    // the size a panel starts growing from, read once by the panel that opens: the card
    // it takes over, else the pill
    function takeOver() {
        const from = takeoverW > 0 ? { w: takeoverW, h: takeoverH } : { w: pillWidth, h: pillHeight }
        takeoverW = 0
        takeoverH = 0
        return from
    }

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
