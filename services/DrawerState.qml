pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

// Open state of the control drawer on the right edge. Opened by the bar's
// control icon, or `qs ipc call drawer toggle`.
Singleton {
    id: root

    property bool open: false

    function toggle() { open = !open }
    function show() { open = true }
    function hide() { open = false }

    IpcHandler {
        target: "drawer"
        function toggle(): void { root.toggle() }
        function show(): void { root.show() }
        function hide(): void { root.hide() }
    }
}
