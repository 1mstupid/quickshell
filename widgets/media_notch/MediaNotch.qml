import QtQuick
import Quickshell
import Quickshell.Wayland
import QtQuick.Effects
import "../../services"
import "../notch"
import "../bar/media"

// The now-playing strip: the bar's media wave opens it. It grows out of the bar
// pill the way the focus notch does and shows the track, its progress and the
// transport. It is its own view and never opens the desktop MediaWidget. A
// click outside, Escape, or the wave closes it.
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

    readonly property int panelW: 380
    readonly property int panelH: 164
    readonly property int pad: 18

    // 0 = the bar pill, 1 = the full strip
    property real t: 0

    MediaState { id: media; active: root.visible }

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
        color: Theme.bg
        clip: true

        // clicks on the strip stay on the strip, not the catcher behind it
        MouseArea { anchors.fill: parent }

        Item {
            id: keyHost
            anchors.fill: parent
            focus: true
            Keys.onEscapePressed: MediaNotchState.hide()
        }

        // transport button: a glyph that brightens under the pointer
        component Glyph: Text {
            id: glyph
            property bool allowed: true
            signal tapped()
            color: !allowed ? Qt.alpha(Theme.fg, 0.25)
                 : ma.containsMouse ? Theme.accent : Theme.fg
            font.family: Theme.fontFamily
            font.pixelSize: 20
            Behavior on color { ColorAnimation { duration: 120 } }

            MouseArea {
                id: ma
                anchors.fill: parent
                anchors.margins: -8
                hoverEnabled: true
                cursorShape: glyph.allowed ? Qt.PointingHandCursor : Qt.ArrowCursor
                onClicked: if (glyph.allowed) glyph.tapped()
            }
        }

        // content fades in during the second half of the morph
        Column {
            anchors.fill: parent
            anchors.margins: root.pad
            spacing: 14
            opacity: Math.max(0, (root.t - 0.5) * 2)

            // cover, then title and artist
            Row {
                width: parent.width
                height: 52
                spacing: 14

                Item {
                    id: thumb
                    width: 52
                    height: 52

                    Image {
                        id: thumbImage
                        anchors.fill: parent
                        source: media.player?.trackArtUrl ?? ""
                        fillMode: Image.PreserveAspectCrop
                        asynchronous: true
                        sourceSize.width: 104
                        layer.enabled: status === Image.Ready
                        layer.effect: MultiEffect {
                            maskEnabled: true
                            maskSource: thumbMask
                        }
                    }

                    // hidden rounded square, used only to mask the cover
                    Item {
                        id: thumbMask
                        anchors.fill: parent
                        visible: false
                        layer.enabled: true

                        Rectangle {
                            anchors.fill: parent
                            radius: 10
                            color: "white"
                        }
                    }
                }

                Column {
                    anchors.verticalCenter: parent.verticalCenter
                    width: parent.width - thumb.width - parent.spacing
                    spacing: 3

                    Text {
                        width: parent.width
                        text: media.player?.trackTitle ?? ""
                        elide: Text.ElideRight
                        color: Theme.fg
                        font.family: Theme.fontFamily
                        font.pixelSize: 15
                        font.bold: true
                    }
                    Text {
                        width: parent.width
                        text: media.artistText
                        elide: Text.ElideRight
                        color: Qt.alpha(Theme.fg, 0.55)
                        font.family: Theme.fontFamily
                        font.pixelSize: 12
                    }
                }
            }

            // elapsed, progress and total
            Item {
                width: parent.width
                height: 14

                Text {
                    id: elapsed
                    anchors.left: parent.left
                    anchors.verticalCenter: parent.verticalCenter
                    width: 40
                    text: media.fmt(media.pos)
                    color: Qt.alpha(Theme.fg, 0.55)
                    font.family: Theme.fontFamilyAlt
                    font.pixelSize: 11
                }
                Text {
                    id: total
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    width: 40
                    horizontalAlignment: Text.AlignRight
                    text: media.timed ? media.fmt(media.len) : ""
                    color: Qt.alpha(Theme.fg, 0.55)
                    font.family: Theme.fontFamilyAlt
                    font.pixelSize: 11
                }
                Rectangle {
                    anchors.left: elapsed.right
                    anchors.right: total.left
                    anchors.leftMargin: 10
                    anchors.rightMargin: 10
                    anchors.verticalCenter: parent.verticalCenter
                    height: 3
                    radius: 2
                    color: Qt.alpha(Theme.fg, 0.2)

                    Rectangle {
                        height: parent.height
                        radius: parent.radius
                        color: Theme.fg
                        width: parent.width * (media.timed ? Math.min(1, media.pos / media.len) : 0)
                    }
                }
            }

            // transport
            Row {
                anchors.horizontalCenter: parent.horizontalCenter
                height: 34
                spacing: 40

                Glyph {
                    anchors.verticalCenter: parent.verticalCenter
                    text: "󰒮"
                    allowed: media.player?.canGoPrevious ?? false
                    onTapped: media.player.previous()
                }
                Glyph {
                    anchors.verticalCenter: parent.verticalCenter
                    font.pixelSize: 26
                    text: media.playing ? "󰏤" : "󰐊"
                    allowed: media.player?.canTogglePlaying ?? false
                    onTapped: media.player.togglePlaying()
                }
                Glyph {
                    anchors.verticalCenter: parent.verticalCenter
                    text: "󰒭"
                    allowed: media.player?.canGoNext ?? false
                    onTapped: media.player.next()
                }
            }
        }
    }
}
