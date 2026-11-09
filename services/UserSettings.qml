pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

// Widget visibility, read from ~/.local/xdg/config/settings.json:
//   {"usageRing": true, "focusWidget": true, "todoWidget": true, "habitsWidget": true}
// and what the control drawer offers (brightness and powerProfile also need the
// hardware, so a desktop shows neither whatever the file says):
//   {"wifi": true, "bluetooth": true, "vpn": true, "brightness": true, "powerProfile": true,
//    "nightLight": true, "keepAwake": true, "screenshot": true}
// (bluetooth and vpn also need an adapter and a VPN profile to show)
// A missing file, a bad file or a missing key keeps the default (shown). The
// file is read on start and whenever it changes. The IPC toggles change the
// running value only, so the file stays the source of truth. The four corner
// widgets are the exception: once layout.json has a `visible` for one, that
// wins, and their toggles write it (see WidgetLayout).
Singleton {
    id: root

    readonly property string path: Quickshell.env("HOME") + "/.local/xdg/config/settings.json"

    property bool usageRing: true
    property bool focusWidget: true
    property bool todoWidget: true
    property bool habitsWidget: true
    property bool wifi: true
    property bool bluetooth: true
    property bool vpn: true
    property bool brightness: true
    property bool powerProfile: true
    property bool nightLight: true
    property bool keepAwake: true
    property bool screenshot: true

    function parse(t) {
        let d = null
        try {
            d = JSON.parse(t)
        } catch (e) {
            d = null
        }
        if (typeof d !== "object" || d === null)
            d = {}
        usageRing = typeof d.usageRing === "boolean" ? d.usageRing : true
        focusWidget = typeof d.focusWidget === "boolean" ? d.focusWidget : true
        todoWidget = typeof d.todoWidget === "boolean" ? d.todoWidget : true
        habitsWidget = typeof d.habitsWidget === "boolean" ? d.habitsWidget : true
        wifi = typeof d.wifi === "boolean" ? d.wifi : true
        bluetooth = typeof d.bluetooth === "boolean" ? d.bluetooth : true
        vpn = typeof d.vpn === "boolean" ? d.vpn : true
        brightness = typeof d.brightness === "boolean" ? d.brightness : true
        powerProfile = typeof d.powerProfile === "boolean" ? d.powerProfile : true
        nightLight = typeof d.nightLight === "boolean" ? d.nightLight : true
        keepAwake = typeof d.keepAwake === "boolean" ? d.keepAwake : true
        screenshot = typeof d.screenshot === "boolean" ? d.screenshot : true
    }

    FileView {
        path: root.path
        watchChanges: true
        onFileChanged: reload()
        onLoaded: root.parse(text())
        onLoadFailed: root.parse("")
    }
}
