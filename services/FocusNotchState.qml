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

    function toggle() { openRequested = !openRequested }
    function show() { openRequested = true }
    function hide() { openRequested = false }

    IpcHandler {
        target: "focusnotch"
        function toggle(): void { root.toggle() }
        function show(): void { root.show() }
        function hide(): void { root.hide() }
    }
}
