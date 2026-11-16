pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import "Settings.js" as Schema

// The settings, read from ~/.local/xdg/config/settings.json. What can be set, with its type
// and default, is listed in Settings.js. Widget visibility:
//   {"usageRing": true, "focusWidget": true, "todoWidget": true, "habitsWidget": true,
//    "mediaWidget": true}
// and what the control drawer offers (brightness and powerProfile also need the
// hardware, so a desktop shows neither whatever the file says):
//   {"wifi": true, "bluetooth": true, "vpn": true, "brightness": true, "powerProfile": true,
//    "nightLight": true, "keepAwake": true, "screenshot": true}
// (bluetooth and vpn also need an adapter and a VPN profile to show)
// and the shape of the bar: {"pill": true} makes the notch a floating pill and hides
// the screen border. Unlike the others it is off when missing.
// The rounding of the notch and of every panel that grows from it, in pixels, is
// {"cornerRadius": 26}; it never goes past half the shorter side of what it rounds, so
// the small bar pill is a capsule and the radius opens up as a panel grows.
// Fonts are {"bodyFont": "SFProText Nerd Font", "displayFont": "SFProDisplay Nerd Font"}, and the
// clocks {"clock24": true}.
// A missing file, a bad file or a missing key keeps the default, and so does a value of the
// wrong type; a number outside its range is held to it. The file is read on start and whenever
// it changes. `set(key, value)` changes one setting and writes the file, and keys that
// Settings.js does not list are kept. The IPC toggles change the running value only, so the
// file stays the source of truth. The four corner widgets are the exception: once
// layout.json has a `visible` for one, that wins, and their toggles write it (see WidgetLayout).
Singleton {
    id: root

    readonly property string path: Quickshell.env("HOME") + "/.local/xdg/config/settings.json"

    // the defaults are the list's, so that there is one place for them
    property bool usageRing: Schema.defaultOf("usageRing")
    property bool focusWidget: Schema.defaultOf("focusWidget")
    property bool todoWidget: Schema.defaultOf("todoWidget")
    property bool habitsWidget: Schema.defaultOf("habitsWidget")
    property bool mediaWidget: Schema.defaultOf("mediaWidget")
    property bool wifi: Schema.defaultOf("wifi")
    property bool bluetooth: Schema.defaultOf("bluetooth")
    property bool vpn: Schema.defaultOf("vpn")
    property bool brightness: Schema.defaultOf("brightness")
    property bool powerProfile: Schema.defaultOf("powerProfile")
    property bool nightLight: Schema.defaultOf("nightLight")
    property bool keepAwake: Schema.defaultOf("keepAwake")
    property bool screenshot: Schema.defaultOf("screenshot")
    property bool workspaces: Schema.defaultOf("workspaces")

    property bool battery: Schema.defaultOf("battery")
    property bool network: Schema.defaultOf("network")
    property bool wave: Schema.defaultOf("wave")
    property bool recording: Schema.defaultOf("recording")
    property bool pomo: Schema.defaultOf("pomo")
    // the faces of the text: the body font and the one for the big figures
    property string bodyFont: Schema.defaultOf("bodyFont")
    property string displayFont: Schema.defaultOf("displayFont")
    // 24 hours on the clocks, or 12 with AM and PM
    property bool clock24: Schema.defaultOf("clock24")
    readonly property string clockFormat: clock24 ? "HH:mm" : "h:mm AP"
    // the bar and its panels as a floating pill, without the screen border
    property bool pill: Schema.defaultOf("pill")
    // 26 is the control panel's, the one the others follow
    property real cornerRadius: Schema.defaultOf("cornerRadius")

    // what the file last said, for every setting, and its keys that are not settings
    property var saved: Schema.parse("").values
    property var extra: ({})

    function parse(t) {
        const r = Schema.parse(t)
        saved = r.values
        extra = r.extra
        for (const s of Schema.SETTINGS)
            root[s.key] = r.values[s.key]
    }

    // Changes one setting and writes the file; the watcher reloads the same content afterwards,
    // which changes nothing. It writes what the file said plus this one value, not the running
    // values, so an IPC toggle is not made permanent by changing something else.
    function set(key, value) {
        const s = Schema.find(key)
        if (!s)
            return
        const v = Schema.normalize(s, value)
        if (v === undefined)
            return
        root[key] = v
        saved = Object.assign({}, saved, { [key]: v })
        file.setText(Schema.serialize(saved, extra))
    }

    // qs ipc call pill toggle
    IpcHandler {
        target: "pill"
        function toggle(): void { root.pill = !root.pill }
    }

    FileView {
        id: file
        path: root.path
        atomicWrites: true
        watchChanges: true
        onFileChanged: reload()
        onLoaded: root.parse(text())
        onLoadFailed: root.parse("")
    }
}
