pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

// Menu state: whether the bar is expanded into the menu, and which tab is
// shown. Opened by the clock, by a tab click, or `qs ipc call menu toggle`.
Singleton {
    id: root

    // icon-only tabs; the order is the order in the bar
    readonly property var tabs: [
        { name: "Todo", icon: "\uDB80\uDD2C" },
        { name: "Habits", icon: "\uDB80\uDCED" },
        { name: "Pomodoro", icon: "\uDB81\uDD1B" },
        { name: "Wi-Fi", icon: "\uDB81\uDDA9" },
        { name: "Bluetooth", icon: "\uDB80\uDCAF" },
        { name: "VPN", icon: "\uDB82\uDD9D" },
        { name: "Usage", icon: "\uDB80\uDF1F" }
    ]

    // the menu's size; its height is the bar's height plus the panel
    readonly property int menuW: 380
    readonly property int panelH: 220

    property bool open: false
    property int tab: 0

    function toggle() { open = !open }
    function show() { open = true }
    function hide() { open = false }
    function select(i) {
        tab = i
        open = true
    }

    IpcHandler {
        target: "menu"
        function toggle(): void { root.toggle() }
        function show(): void { root.show() }
        function hide(): void { root.hide() }
    }
}
