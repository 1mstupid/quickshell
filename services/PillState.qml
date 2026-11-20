pragma Singleton
import QtQuick
import Quickshell

// Shared state for the bar pill and the morphing panels (wallpaper and colorscheme pickers,
// app launcher, control panel, lockscreen). The bar fades its pill from `progress` while a panel
// owns it, and the owning panel grows out of the origin pill.
QtObject {
    id: root

    // which panel owns the pill: "", "wallpapers", "colorschemes", "applauncher", "clipboard", "focus", "share", or "lock"
    property string owner: ""
    readonly property bool active: owner !== ""
    // true from the start of a panel's close until the pill is released: the panel is shrinking
    // back into the pill, so the bar's content returns with it instead of after the morph
    property bool returning: false

    // how long a panel takes to grow out of the pill, and to go back: the same for all of them
    readonly property int morphMs: Math.round(UserSettings.morphMs)
    // the lock screen's fade-in and reversed unlock: longer, so the elastic bounce reads
    readonly property int lockMs: 420
    // how far the pill drops in the lock state; the bar's pill drops by the same amount while locked
    readonly property int lockDrop: 20
    // true from the lock until the centre clock lands back on the bar: the bar's pill sits dropped
    property bool pillDropped: false
    // true while the lock waits for the open panels to close back into the pill
    property bool locking: false
    // the bar pill's landing bounce: an amplitude of 2 overshoots about 17 px on the 20 px drop
    readonly property real pillAmplitude: 2.0

    // The morph overshoots and settles like a spring, both ways. On the close the overshoot dips
    // below the pill, so the panels clamp their size at 0 (the card holds at pill size and springs
    // back). The period is the bounce (Qt ignores an amplitude below 1, so it is the only knob).
    readonly property int openEase: Easing.OutElastic
    readonly property real easeAmplitude: 0.3
    readonly property real easePeriod: UserSettings.morphPeriod

    // The card a panel gave up when another panel took the pill. The next panel grows out of
    // it instead of out of the pill, so the two hand over without a pill-sized step. Cleared
    // once nothing owns the pill, so a stale card never starts a later panel.
    property real takeoverW: 0
    property real takeoverH: 0
    onOwnerChanged: if (owner === "") { takeoverW = 0; takeoverH = 0; returning = false }

    // A panel asks for the pill with its name. A switch always goes through at once: the
    // panel giving way hands its card over (giveWay), so a quick switch does not cut a morph
    // short and nothing waits. Refusing it would drop the keypress instead.
    function claim(name) {
        owner = name
        returning = false
        return true
    }

    // the size a panel starts growing from, read once by the panel that opens: the card
    // it takes over, else the pill
    function takeOver() {
        const from = takeoverW > 0 ? { w: takeoverW, h: takeoverH, taken: true }
                                   : { w: pillWidth, h: pillHeight, taken: false }
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
