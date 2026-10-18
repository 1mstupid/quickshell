import QtQuick
import QtQuick.Effects

// Spinning album-art disc for the bar. Shown while an MPRIS player has a
// track; spins while playing, click toggles play/pause.
Item {
    id: root

    implicitWidth: 16
    implicitHeight: 16

    // own instance, like the Media pill and dashboard
    MediaState { id: media }

    opacity: media.player !== null ? 1 : 0
    visible: opacity > 0
    Behavior on opacity {
        NumberAnimation { duration: 150; easing.type: Easing.OutQuad }
    }

    // hidden circle, only used as the mask source
    Item {
        id: mask
        width: 16
        height: 16
        visible: false
        layer.enabled: true
        Rectangle { anchors.fill: parent; radius: width / 2; color: "white" }
    }

    Item {
        id: disc
        anchors.fill: parent
        layer.enabled: true
        layer.effect: MultiEffect {
            maskEnabled: true
            maskSource: mask
        }

        PlayerArtwork {
            anchors.fill: parent
            source: media.player?.trackArtUrl ?? ""
            trackNumber: ""
        }
    }

    // spin by nudging the angle, so a pause keeps the current position
    Timer {
        running: media.playing
        interval: 16
        repeat: true
        onTriggered: disc.rotation = (disc.rotation + 1.5) % 360
    }

    // 400 ms debounce; the icon follows the player's reported state
    Timer { id: cooldown; interval: 400 }

    MouseArea {
        anchors.fill: parent
        cursorShape: Qt.PointingHandCursor
        onClicked: {
            if (!media.player || cooldown.running) return
            cooldown.restart()
            media.player.togglePlaying()
        }
    }
}
