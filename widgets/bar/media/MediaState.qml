import QtQuick
import Quickshell.Services.Mpris
import "../../../components"


// Shared now-playing state (MPRIS), no visuals. The bar's Media pill and
// the dashboard's Media page each own one, so they follow the same players
// but keep their own pinned player and dismissed state.
Item {
    id: root

    width: 0
    height: 0

    // false stops position polling while nothing shows this state
    property bool active: true

    // popup-pinned player; falls back to auto when it disappears
    property var manual: null
    readonly property var player: {
        const ps = Mpris.players.values
        if (manual && ps.indexOf(manual) >= 0)
            return manual
        for (let i = 0; i < ps.length; i++)
            if (ps[i].playbackState === MprisPlaybackState.Playing)
                return ps[i]
        return ps.length > 0 ? ps[0] : null
    }
    readonly property bool playing: player !== null
        && player.playbackState === MprisPlaybackState.Playing
    // a track is loaded, playing or paused; stopped or no player is not
    readonly property bool present: player !== null
        && player.playbackState !== MprisPlaybackState.Stopped

    // middle-click dismiss; cleared when the track or player changes
    property bool dismissed: false
    onPlayerChanged: dismissed = false

    // MPRIS reports artists as an array, but some players send a string
    readonly property string artistText: {
        const a = player?.trackArtists
        if (!a) return ""
        return Array.isArray(a) ? a.join(", ") : String(a)
    }

    // MPRIS doesn't push position updates, so tick it while playing
    property real pos: 0
    readonly property real len: player?.length ?? 0
    readonly property bool timed: len > 0 && isFinite(len)

    Timer {
        running: root.active && root.playing
        interval: 1000
        repeat: true
        triggeredOnStart: true
        onTriggered: root.pos = root.player?.position ?? 0
    }

    // re-read immediately on track change or seek while paused
    Connections {
        target: root.player
        function onTrackTitleChanged() {
            root.pos = root.player?.position ?? 0
            root.dismissed = false
        }
        function onPositionChanged() {
            root.pos = root.player?.position ?? 0
        }
    }

    // right click on the wave: stop the player outright
    function kill() {
        if (player && player.canStop)
            player.stop()
    }

    function fmt(s) {
        s = Math.max(0, Math.round(s))
        const m = Math.floor(s / 60), r = s % 60
        return (m >= 60 ? Math.floor(m / 60) + ":" + String(m % 60).padStart(2, "0")
                        : m) + ":" + String(r).padStart(2, "0")
    }
}
