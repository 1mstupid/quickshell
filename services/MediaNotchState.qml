pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

// Open state of the now-playing strip under the bar's media wave. Opened by the
// wave, or `qs ipc call medianotch toggle`; MediaNotch reacts to it.
Singleton {
    id: root

    property bool open: false

    function toggle() { open = !open }
    function show() { open = true }
    function hide() { open = false }

    IpcHandler {
        target: "medianotch"
        function toggle(): void { root.toggle() }
        function show(): void { root.show() }
        function hide(): void { root.hide() }
    }
}
