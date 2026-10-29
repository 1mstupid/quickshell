pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

// Open state of the usage dashboard. Opened with `qs ipc call dashboard toggle`;
// Dashboard reacts to it.
Singleton {
    id: root

    property bool open: false

    function toggle() { open = !open }
    function show()   { open = true }
    function hide()   { open = false }

    IpcHandler {
        target: "dashboard"
        function toggle(): void { root.toggle() }
        function show(): void { root.show() }
        function hide(): void { root.hide() }
    }
}
