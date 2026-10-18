import QtQuick
import Quickshell
import Quickshell.Wayland
import Quickshell.Services.Pipewire

PanelWindow {
    id: osd

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
        onTriggered: osd.armed = true
    }

    Timer {
        id: hideTimer
        interval: 1200
        onTriggered: osd.shown = false
    }

    function poke() {
        if (!armed) return
        shown = true
        hideTimer.restart()
    }

    onVolumeChanged: poke()
    onMutedChanged: poke()

    anchors {
        right: true
        top: true
        bottom: true
    }
    implicitWidth: 56
    exclusiveZone: 0
    color: "transparent"
    mask: Region {}   // empty mask: clicks pass through the window

    Rectangle {
        id: panel
        anchors.right: parent.right
        anchors.rightMargin: 14
        anchors.verticalCenter: parent.verticalCenter
        width: 22
        height: 200
        radius: 6
        color: Qt.alpha(Theme.bg, 0.6)
        border.width: 1
        border.color: Qt.alpha(osd.muted ? Theme.fg : Theme.accent, 0.35)

        opacity: osd.shown ? 1 : 0
        x: osd.shown ? 0 : 12
        Behavior on opacity { NumberAnimation { duration: 150; easing.type: Easing.OutQuad } }
        Behavior on x { NumberAnimation { duration: 180; easing.type: Easing.OutExpo } }

        Rectangle {
            id: track
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.top: parent.top
            anchors.bottom: label.top
            anchors.topMargin: 12
            anchors.bottomMargin: 8
            width: 4
            radius: 2
            color: Qt.alpha(Theme.fg, 0.08)

            Rectangle {
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.bottom: parent.bottom
                height: parent.height * (osd.muted ? 0 : osd.volume / 100)
                radius: parent.radius
                color: osd.muted ? Qt.alpha(Theme.fg, 0.4) : Theme.accent

                Behavior on height { NumberAnimation { duration: 90; easing.type: Easing.OutCubic } }
            }
        }

        Text {
            id: label
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            anchors.bottomMargin: 8
            horizontalAlignment: Text.AlignHCenter
            text: osd.muted ? "MU" : osd.volume.toString()
            color: osd.muted ? Qt.alpha(Theme.fg, 0.5) : Theme.fg
            font.family: "monospace"
            font.pixelSize: 9
            font.bold: true
            elide: Text.ElideNone
        }
    }
}
