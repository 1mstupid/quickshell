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
        interval: 1500
        onTriggered: osd.shown = false
    }

    function poke() {
        if (!armed) return
        shown = true
        hideTimer.restart()
    }

    onVolumeChanged: poke()
    onMutedChanged: poke()

    // Sidebar along the right edge, doesn't reserve space
    anchors {
        right: true
        top: true
        bottom: true
    }
    implicitWidth: 80
    exclusiveZone: 0
    color: "transparent"
    mask: Region {}   // empty mask: clicks pass through the window

    Rectangle {
        id: panel
        anchors.right: parent.right
        anchors.rightMargin: 16
        anchors.verticalCenter: parent.verticalCenter
        width: 48
        height: 280
        radius: 24
        color: Qt.alpha(Theme.bg, 0.25)   // swap for your Theme colors

        // fades and slides in/out; the window itself stays mapped
        opacity: osd.shown ? 1 : 0
        x: osd.shown ? 0 : 20
        Behavior on opacity { NumberAnimation { duration: 200 } }
        Behavior on x { NumberAnimation { duration: 200; easing.type: Easing.OutCubic } }

        // track
        Rectangle {
            id: track
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.top: parent.top
            anchors.bottom: label.top
            anchors.topMargin: 20
            anchors.bottomMargin: 12
            width: 10
            radius: 5
            color: Qt.alpha(Theme.accent, 0.15)

            // fill grows from the bottom
            Rectangle {
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.bottom: parent.bottom
                height: parent.height * (osd.muted ? 0 : osd.volume / 100)
                radius: parent.radius
                color: osd.muted ? Qt.alpha(Theme.fg, 0.45) : Theme.green

                Behavior on height { NumberAnimation { duration: 120 } }
            }
        }

        Text {
            id: label
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.bottom: parent.bottom
            anchors.bottomMargin: 16
            text: osd.muted ? "--" : osd.volume + "%"
            color: Theme.fg
            font.pixelSize: 14
        }
    }
}
