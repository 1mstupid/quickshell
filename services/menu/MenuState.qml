pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

// Menu state: whether the bar is expanded into the menu, which group of pages
// is shown, and which page inside that group. Opened by the clock, by a group
// click, or `qs ipc call menu toggle`.
Singleton {
    id: root

    // three groups, in bar order; each lists its pages in the order of its switch
    readonly property var tabs: [
        { name: "Tasks", icon: "󰄬", pages: ["todo", "habits"] },
        { name: "Focus", icon: "󰔛", pages: ["pomodoro", "usage"] },
        { name: "Network", icon: "󰖩", pages: ["wi-fi", "bluetooth", "vpn"] }
    ]

    // the menu's size; its height is the bar's height plus the panel
    readonly property int menuW: 380
    // 230 for the page, plus the 22 px row of page names above it
    readonly property int panelH: 252

    property bool open: false
    property int tab: 0
    // the page shown in each group, by index into that group's pages; kept per group
    property var page: [0, 0, 0]

    function toggle() { open = !open }
    function show() { open = true }
    function hide() { open = false }
    function select(i) {
        tab = i
        open = true
    }
    function selectPage(g, p) {
        const next = page.slice()
        next[g] = p
        page = next
    }

    IpcHandler {
        target: "menu"
        function toggle(): void { root.toggle() }
        function show(): void { root.show() }
        function hide(): void { root.hide() }
    }
}
