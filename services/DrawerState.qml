pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

// Open state of the control panel, which is a page of the focus notch (see
// FocusNotchState). Opened by the gear on the notch's header, or `qs ipc call drawer toggle`.
Singleton {
    id: root

    readonly property bool open: FocusNotchState.openRequested && FocusNotchState.page === "control"

    function toggle() { FocusNotchState.toggleControl() }
    function show() { FocusNotchState.showControl() }
    function hide() { if (open) FocusNotchState.hide() }

    IpcHandler {
        target: "drawer"
        function toggle(): void { root.toggle() }
        function show(): void { root.show() }
        function hide(): void { root.hide() }
    }
}
