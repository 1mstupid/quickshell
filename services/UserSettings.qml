pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import "Settings.js" as Schema

// The settings, from the [settings] table of ~/.config/lumin/config.toml (see Config). What can
// be set, with its type and default, is listed in Settings.js. Widget visibility, what the
// control drawer offers (brightness and powerProfile also need the hardware), the shape of
// the bar (pill = true makes the notch a floating pill and hides the screen border; it is off
// when missing), the rounding in pixels (cornerRadius = 26, which never goes past half the
// shorter side of what it rounds), the fonts (bodyFont, displayFont) and clock24 are all keys
// of that table, for example:
//   [settings]
//   pill = true
//   cornerRadius = 26
//   usageRing = true
// (bluetooth and vpn also need an adapter and a VPN profile to show)
// A missing table, a missing key, or a value of the wrong type keeps the default; a number
// outside its range is held to it. `set(key, value)` changes one setting in the file, which is
// read back afterwards. The IPC toggles change the running value only, so the file stays the
// source of truth. The four corner widgets are the exception: once layout.json has a `visible`
// for one, that wins, and their toggles write it (see WidgetLayout).
Singleton {
    id: root

    // the defaults are the list's, so that there is one place for them
    property bool usageRing: Schema.defaultOf("usageRing")
    property bool focusWidget: Schema.defaultOf("focusWidget")
    property bool focusNotch: Schema.defaultOf("focusNotch")
    property bool focusHome: Schema.defaultOf("focusHome")
    property bool focusWork: Schema.defaultOf("focusWork")
    property bool focusPorts: Schema.defaultOf("focusPorts")
    property bool focusUsage: Schema.defaultOf("focusUsage")
    property bool focusShare: Schema.defaultOf("focusShare")
    property bool focusBuds: Schema.defaultOf("focusBuds")
    property bool focusTray: Schema.defaultOf("focusTray")
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
    property bool sounds: Schema.defaultOf("sounds")
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
    // the panel morph: its time in ms, and the period of the elastic curve (see PillState)
    property real morphMs: Schema.defaultOf("morphMs")
    property real morphPeriod: Schema.defaultOf("morphPeriod")

    // takes the [settings] table; a key that is missing or of the wrong type keeps its default
    function parse(table) {
        for (const s of Schema.SETTINGS) {
            const v = Schema.normalize(s, table?.[s.key])
            root[s.key] = v === undefined ? s.def : v
        }
    }

    // Changes one setting in config.toml. Only that key is written, so an IPC toggle is not made
    // permanent by changing something else.
    function set(key, value) {
        const s = Schema.find(key)
        if (!s)
            return
        const v = Schema.normalize(s, value)
        if (v === undefined)
            return
        root[key] = v
        Config.set("settings", key, v)
    }

    Connections {
        target: Config
        function onDataChanged() { root.parse(Config.data.settings) }
    }

    // qs ipc call pill toggle
    IpcHandler {
        target: "pill"
        function toggle(): void { root.pill = !root.pill }
    }
}
