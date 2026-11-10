import QtQuick
import Quickshell
import Quickshell.Wayland
import "../../services"
import "../notch"
import "../bar/media"

// The now-playing strip: the bar's media wave opens it. It grows out of the bar
// pill the way the focus notch does, showing the track with play/pause and next.
// It is its own view and never opens the desktop MediaWidget. A click outside,
// Escape, or the wave closes it.
PanelWindow {
    id: root

    screen: PillState.originScreen
    visible: false

    anchors {
        top: true
        left: true
        right: true
    }
    implicitHeight: PillState.pillTop + panelH + 12

    color: "transparent"
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: root.visible ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None
    WlrLayershell.namespace: "quickshell-medianotch"

    // the band takes clicks while the strip is open, so a click outside closes it
    mask: Region { item: catcher }

    readonly property int panelW: 360
    readonly property int panelH: 78
    readonly property int pad: 14

    // 0 = the bar pill, 1 = the full strip
    property real t: 0

    MediaState { id: media }

    function openStrip() {
        PillState.owner = "medianotch"
        visible = true
        morph.stop()
        morph.from = root.t
        morph.to = 1
        morph.start()
    }

    function closeStrip() {
        morph.stop()
        morph.from = root.t
        morph.to = 0
        morph.start()
    }

    onVisibleChanged: {
        if (visible)
            keyHost.forceActiveFocus()
    }

    NumberAnimation {
        id: morph
        target: root
        property: "t"
        duration: 360
        easing.type: Easing.InOutCubic
        onFinished: {
            if (root.t < 0.5) {
                root.visible = false
                if (PillState.owner === "medianotch")
                    PillState.owner = ""
            }
        }
    }

    // nothing to show without a track, so the strip cannot stay open
    Connections {
        target: media
        function onPresentChanged() {
            if (!media.present)
                MediaNotchState.hide()
        }
    }

    Connections {
        target: MediaNotchState
        function onOpenChanged() {
            if (MediaNotchState.open && media.present) {
                root.openStrip()
            } else {
                if (MediaNotchState.open)
                    MediaNotchState.hide()
                root.closeStrip()
            }
        }
    }

    // another panel took the pill, so the strip gives way
    Connections {
        target: PillState
        function onOwnerChanged() {
            if (PillState.owner !== "medianotch" && root.visible)
                MediaNotchState.hide()
        }
    }

    MouseArea {
        id: catcher
        anchors.fill: parent
        onClicked: MediaNotchState.hide()
    }

    Notch {
        bodyWidth: card.width
        bodyHeight: card.height
        x: card.x - bodyX
        y: card.y
    }

    Rectangle {
        id: card

        readonly property real fromW: PillState.pillWidth
        readonly property real fromH: PillState.pillHeight

        width: fromW + (root.panelW - fromW) * root.t
        height: fromH + (root.panelH - fromH) * root.t
        x: (root.width - width) / 2
        y: PillState.pillTop
        color: "transparent"
        clip: true

        // clicks on the strip stay on the strip, not the catcher behind it
        MouseArea { anchors.fill: parent }

        Item {
            id: keyHost
            anchors.fill: parent
            focus: true
            Keys.onEscapePressed: MediaNotchState.hide()
        }

        // content fades in during the second half of the morph
        Row {
            anchors.verticalCenter: parent.verticalCenter
            anchors.horizontalCenter: parent.horizontalCenter
            spacing: 12
            opacity: Math.max(0, (root.t - 0.5) * 2)

            Rectangle {
                id: art
                anchors.verticalCenter: parent.verticalCenter
                width: 46
                height: 46
                radius: 8
                color: Qt.alpha(Theme.fg, 0.06)
                clip: true

                Image {
                    id: artImage
                    anchors.fill: parent
                    source: media.player?.trackArtUrl ?? ""
                    fillMode: Image.PreserveAspectCrop
                    asynchronous: true
                    sourceSize.width: 92
                }
                Text {
                    anchors.centerIn: parent
                    visible: artImage.status !== Image.Ready
                    text: "󰝚"
                    color: Qt.alpha(Theme.fg, 0.3)
                    font.family: Theme.fontFamily
                    font.pixelSize: 20
                }
            }

            Column {
                anchors.verticalCenter: parent.verticalCenter
                width: 190
                spacing: 3

                MarqueeText {
                    width: parent.width
                    text: media.player?.trackTitle ?? ""
                    color: Theme.fg
                    font.family: Theme.fontFamily
                    font.pixelSize: 14
                    font.bold: true
                }
                MarqueeText {
                    width: parent.width
                    text: media.artistText
                    color: Qt.alpha(Theme.fg, 0.6)
                    font.family: Theme.fontFamily
                    font.pixelSize: 12
                }
            }

            Row {
                anchors.verticalCenter: parent.verticalCenter
                spacing: 12

                Text {
                    id: playGlyph
                    text: media.playing ? "󰏤" : "󰐊"
                    color: playMa.containsMouse ? Theme.accent : Theme.fg
                    font.family: Theme.fontFamily
                    font.pixelSize: 20
                    Behavior on color { ColorAnimation { duration: 120 } }

                    MouseArea {
                        id: playMa
                        anchors.fill: parent
                        anchors.margins: -8
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: if (media.player?.canTogglePlaying) media.player.togglePlaying()
                    }
                }
                Text {
                    text: "󰒭"
                    color: nextMa.containsMouse ? Theme.accent : Theme.fg
                    font.family: Theme.fontFamily
                    font.pixelSize: 20
                    Behavior on color { ColorAnimation { duration: 120 } }

                    MouseArea {
                        id: nextMa
                        anchors.fill: parent
                        anchors.margins: -8
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: if (media.player?.canGoNext) media.player.next()
                    }
                }
            }
        }
    }
}
