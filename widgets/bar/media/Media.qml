import QtQuick
import Quickshell.Services.Mpris

// Now-playing pill. Click toggles play/pause, scroll skips tracks, right
// click opens MediaPopup, middle click dismisses the pill until the track
// or player changes. The pill stays short; full info is in the popup and
// the dashboard's Media page.
BarModule {
    id: root

    MediaState {
        id: mediaState
        active: root.visible
    }

    visible: mediaState.player !== null && !mediaState.dismissed
        && mediaState.player.playbackState !== MprisPlaybackState.Stopped

    icon: mediaState.playing ? "󰐊" : "󰏤"
    iconColor: Theme.magenta
    label: {
        const p = mediaState.player
        if (!p)
            return ""
        const t = mediaState.artistText !== ""
            ? mediaState.artistText + " — " + p.trackTitle
            : (p.trackTitle ?? "")
        return t.length > 26 ? t.slice(0, 24) + "…" : t
    }
    progress: mediaState.timed ? Math.min(mediaState.pos / mediaState.len, 1) : -1

    onClicked: mouse => {
        if (mouse.button === Qt.RightButton) {
            popup.visible = !popup.visible
        } else if (mouse.button === Qt.MiddleButton) {
            mediaState.dismissed = true
            popup.visible = false
        } else if (mediaState.player && mediaState.player.canTogglePlaying) {
            mediaState.player.togglePlaying()
        }
    }
    onScrolled: dir => {
        const p = mediaState.player
        if (!p)
            return
        if (dir > 0 && p.canGoPrevious)
            p.previous()
        else if (dir < 0 && p.canGoNext)
            p.next()
    }

    MediaPopup {
        id: popup
        anchorItem: root
        media: mediaState
    }
}
