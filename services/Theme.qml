pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import "../widgets/colorscheme/Colorschemes.js" as Schemes

Singleton {
    id: root

    readonly property string configDir: Quickshell.env("HOME") + "/.config"
    property int _barStateLoads: 0
    readonly property bool barStateReady: _barStateLoads >= 2
    Timer {
        running: !root.barStateReady
        interval: 1000
        onTriggered: root._barStateLoads = 2
    }

    // The background is not taken from a scheme: near black, or a pale blue while the scheme
    // in use is a light one (`light` in Colorschemes.js).
    property bool light: false
    property color bg: light ? "#EDF4FE" : "#010101"
    property color altbg: "#161b22"
    property color fg: "#c9d1d9"
    property color border: "#30363d"
    property color primary: "#58a6ff"
    property color secondary: "#8b949e"
    property color alert: "#f85149"
    property color disabled: "#484f58"

    readonly property color accent: primary
    readonly property color selbg: primary
    readonly property color selfg: bg
    readonly property color red: alert
    readonly property color yellow: primary
    readonly property color blue: secondary
    readonly property color green: secondary
    readonly property color cyan: secondary
    readonly property color magenta: secondary

    // SF Pro has two optical sizes: Text is drawn for small sizes (looser
    // spacing, larger x-height), Display for 20 px and up. Nearly all the
    // shell's text is 9 to 15 px, so Text is the default and Display is kept for
    // the big figures. Both are the Nerd Font builds, so icon glyphs work in either.
    // They are the `bodyFont` and `displayFont` settings (the defaults are the SF Pro ones above).
    readonly property string fontFamily: UserSettings.bodyFont
    readonly property string fontFamilyAlt: UserSettings.bodyFont
    // proportional face for titles and labels; glyph icons stay on fontFamily
    readonly property string fontFamilySans: UserSettings.bodyFont
    // numbers and times
    readonly property string fontFamilyNum: UserSettings.bodyFont
    // text at 20 px and up: the timer readouts and the big totals
    readonly property string fontFamilyDisplay: UserSettings.displayFont
    readonly property real autoScale: {
        const s = Quickshell.screens.length > 0 ? Quickshell.screens[0] : null
        const h = s ? s.height : 1080
        return Math.min(Math.max(h / 1080, 0.75), 2.5)
    }

    readonly property int edgeInset: Math.round(8 * autoScale)
    readonly property real barScale: 0.95
    readonly property int fontSize: Math.round(13 * barScale)
    readonly property int iconSize: Math.round(15 * barScale)
    readonly property int moduleHeight: Math.round(26 * barScale)
    readonly property int effectiveBarHeight: 30
    readonly property int cardRadius: 20


    // the scheme in use, written by the colorscheme and wallpaper pickers; none, or one that is
    // not in the list (the wallpaper's own), is dark
    FileView {
        path: Quickshell.env("HOME") + "/.local/xdg/config/colorscheme-current"
        watchChanges: true
        onFileChanged: reload()
        onLoaded: {
            const at = Schemes.indexOfId(text().trim())
            root.light = at >= 0 && Schemes.SCHEMES[at].light === true
        }
        onLoadFailed: root.light = false
    }

    FileView {
        path: root.configDir + "/../.local/state/colors.ini"
        watchChanges: true
        onFileChanged: reload()
        onLoaded: root.parseIni(text())
    }

    function parseIni(t) {
        const map = {}
        for (const line of t.split("\n")) {
            const m = line.match(/^\s*([A-Za-z-]+)\s*=\s*(#[0-9a-fA-F]{3,8})/)
            if (m)
                map[m[1]] = m[2]
        }
        // if (map["background"]) bg = map["background"]
        if (map["background-alt"]) altbg = map["background-alt"]
        if (map["foreground"]) fg = map["foreground"]
        if (map["border"]) border = map["border"]
        if (map["primary"]) primary = map["primary"]
        if (map["secondary"]) secondary = map["secondary"]
        if (map["alert"]) alert = map["alert"]
        if (map["disabled"]) disabled = map["disabled"]
    }
}
