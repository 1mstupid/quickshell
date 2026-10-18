pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

// Live palette sourced from the bspwm theme switcher. The switcher rewrites
// polybar/colors.ini (and colors.sh) in place on every switch, so watching
// that file re-colors the bar with no restart — polybar itself can be
// retired without breaking this. Defaults are github_dark placeholders.
//
// The polybar palette is smaller than dwm's xresources+ANSI set, so the
// semantic names below collapse onto it: red→alert, yellow→primary,
// blue/green/cyan/magenta→secondary. Cohesive by construction.
Singleton {
    id: root

    // config root = parent of the running quickshell dir, derived rather
    // than hardcoded so vendored copies (openbox etc.) need no path edits
    readonly property string configDir: Quickshell.env("HOME") + "/.config"

    // bar height (px) and element scale, persisted to plain files (like
    // weather-location) so the tweaks sliders survive restarts
    property int barHeight: 42
    property real barUserScale: 1.0

    // both state files attempted (present or not); bars gate their first
    // map on this to appear once at final size (openbox re-clamps docks
    // on resize). The timer failsafe guarantees the bar always maps.
    property int _barStateLoads: 0
    readonly property bool barStateReady: _barStateLoads >= 2
    Timer {
        running: !root.barStateReady
        interval: 1000
        onTriggered: root._barStateLoads = 2
    }

    property color bg: "#060706"
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

    readonly property string fontFamily: "Maple Mono NL NF"

    // Resolution-aware base scale from the first output's logical height:
    // 1.0 at 1080p, 1.33 at 1440p, 2.0 at unscaled 4K. An output scale set
    // in mango (the proper hi-dpi fix) shrinks the logical height, so this
    // stays at 1.0 there and nothing is scaled twice.
    readonly property real autoScale: {
        const s = Quickshell.screens.length > 0 ? Quickshell.screens[0] : null
        const h = s ? s.height : 1080
        return Math.min(Math.max(h / 1080, 0.75), 2.5)
    }

    // The bar's inset from the screen edges. Wm.qml sets mango's outer
    // gaps to the same value so windows float with the same margin.
    readonly property int edgeInset: Math.round(8 * autoScale)
    // matches border_radius in config.conf
    readonly property int barRadius: 10

    // In-bar elements follow autoScale × the scale slider; popups stay
    // fixed. barHeight is a floor: the window grows when scaled modules
    // (26px at 1.0, + inset above + 8px padding) outgrow it.
    readonly property real barScale: 0.95
    readonly property int fontSize: Math.round(13 * barScale)
    readonly property int iconSize: Math.round(15 * barScale)
    readonly property int moduleHeight: Math.round(26 * barScale)
    readonly property int effectiveBarHeight: 30

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
        if (map["background-alt"]) altbg = map["background-alt"]
        if (map["foreground"]) fg = map["foreground"]
        if (map["border"]) border = map["border"]
        if (map["primary"]) primary = map["primary"]
        if (map["secondary"]) secondary = map["secondary"]
        if (map["alert"]) alert = map["alert"]
        if (map["disabled"]) disabled = map["disabled"]
    }
}
