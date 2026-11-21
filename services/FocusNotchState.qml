pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

// State of the focus notch, the panel that grows out of the bar's center pill.
// The bar reports whether the pointer is on the pill; the panel decides what to
// do with it. `qs ipc call focusnotch toggle` opens it without the pointer.
Singleton {
    id: root

    // the pointer is on the bar pill of the origin screen
    property bool pillHovered: false

    // asked open from outside (IPC); the panel follows and resets it when it closes
    property bool openRequested: false

    // the page the open panel shows; kept across openings, reset on shell restart
    property string page: "home"
    function setPage(key) { page = key }

    // the pages the settings leave on: a page that is off is left out of the strip and the
    // wheel, and with the notch off or no page left, the notch does not open
    function pageOn(key) {
        switch (key) {
        case "home": return UserSettings.focusHome
        case "work": case "day": case "week": case "focus": return UserSettings.focusWork
        case "ports": return UserSettings.focusPorts
        case "usage": return UserSettings.focusUsage
        case "share": return UserSettings.focusShare
        case "buds": return UserSettings.focusBuds
        default: return true
        }
    }
    readonly property bool available: UserSettings.focusNotch
        && (UserSettings.focusHome || UserSettings.focusWork || UserSettings.focusPorts
            || UserSettings.focusUsage || UserSettings.focusShare || UserSettings.focusBuds)

    // The control panel is a page with no tab: the gear on the header opens it, and
    // `before` is the page it goes back to.
    property string before: "home"
    function showControl() {
        if (page !== "control")
            before = page
        page = "control"
        show()
    }
    function leaveControl() {
        if (page === "control")
            page = before
    }
    // the gear: into the control panel, or back out of it
    function toggleGear() {
        if (page === "control")
            leaveControl()
        else
            showControl()
    }
    // IPC and the bar: opens on the control panel, closes if already there
    function toggleControl() {
        if (openRequested && page === "control")
            hide()
        else
            showControl()
    }

    // the usage page, from `qs ipc call focusnotch usage`; opens it on its own
    function showUsage() {
        page = "usage"
        show()
    }

    function toggle() { openRequested = !openRequested }
    // open on Home, where the notifications are; closes if already there
    function toggleHome() {
        if (openRequested && page === "home") {
            hide()
            return
        }
        page = "home"
        show()
    }
    function show() { openRequested = true }
    function hide() { openRequested = false }

    IpcHandler {
        target: "focusnotch"
        function toggle(): void { root.toggle() }
        function show(): void { root.show() }
        function hide(): void { root.hide() }
        function usage(): void { root.showUsage() }
    }
}
