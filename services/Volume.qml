pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Services.Pipewire

// Default sink volume and a 1.2 s "shown" flag, read by every bar's pill
// so the readout appears inside each bar when the volume changes.
Singleton {
    id: root

    PwObjectTracker {
        objects: [Pipewire.defaultAudioSink]
    }

    readonly property var audio: Pipewire.defaultAudioSink?.audio ?? null
    readonly property bool muted: audio?.muted ?? false
    readonly property int volume: audio ? Math.round(audio.volume * 100) : 0

    property bool shown: false
    property bool armed: false   // ignore the initial values at startup

    Timer {
        interval: 1000
        running: true
        onTriggered: root.armed = true
    }

    Timer {
        id: hideTimer
        interval: 1200
        onTriggered: root.shown = false
    }

    function poke() {
        if (!armed) return
        shown = true
        hideTimer.restart()
    }

    onVolumeChanged: poke()
    onMutedChanged: poke()
}
