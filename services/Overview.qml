pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io

// Overview state. hyprexpo does not report whether it is open, so the shell
// owns the flag and drives hyprexpo from the same toggle. Bound to a key as
// `qs ipc call overview toggle`, so the bar and widgets always agree with it.
Singleton {
    id: root

    property bool open: false

    function toggle() {
        open = !open
        Hyprland.dispatch("hyprexpo:expo toggle")
    }

    IpcHandler {
        target: "overview"
        function toggle(): void { root.toggle() }
    }
}
