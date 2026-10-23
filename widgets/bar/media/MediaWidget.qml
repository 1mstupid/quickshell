import Quickshell
import Quickshell.Wayland
import Quickshell.Io
import QtQuick
import QtQuick.Effects
import "../../../services"

// Media widget. It morphs out of the bar pill, like the launcher and the
// wallpaper picker. Opened by the wave (or `qs ipc call media toggle`),
// closed by Escape, and closed when the track stops (pausing keeps it open).
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
    WlrLayershell.namespace: "quickshell-media"

    readonly property int panelW: 340
    // margins 14 + header 64 + 12 + progress 22 + 12 + controls 36 + margins 14
    readonly property int panelH: 174

    // 0 = the bar pill, 1 = the full widget
    property real t: 0

    MediaState {
        id: media
        active: root.visible
    }

    IpcHandler {
        target: "media"
        function toggle(): void { MediaWidgetState.toggle() }
        function show(): void { MediaWidgetState.show() }
        function hide(): void { MediaWidgetState.hide() }
        function kill(): void { media.kill() }
    }

    // only the card takes clicks; everything around it passes through
    mask: Region { item: card }

    onVisibleChanged: {
        if (visible)
            keyHost.forceActiveFocus()
    }

    function openWidget() {
        PillState.owner = "media"
        visible = true
        morph.stop()
        morph.from = root.t
        morph.to = 1
        morph.start()
    }

    function closeWidget() {
        morph.stop()
        morph.from = root.t
        morph.to = 0
        morph.start()
    }

    NumberAnimation {
        id: morph
        target: root
        property: "t"
        duration: 480
        easing.type: Easing.InOutCubic
        onFinished: {
            if (root.t < 0.5) {
                root.visible = false
                if (PillState.owner === "media")
                    PillState.owner = ""
            }
        }
    }

    Connections {
        target: MediaWidgetState
        function onOpenChanged() {
            if (MediaWidgetState.open)
                root.openWidget()
            else
                root.closeWidget()
        }
    }

    // the track stopping or disappearing closes the widget; pausing does not
    Connections {
        target: media
        function onPresentChanged() {
            if (!media.present)
                MediaWidgetState.hide()
        }
    }

    // another panel took the pill, so this one gives way
    Connections {
        target: PillState
        function onOwnerChanged() {
            if (PillState.owner !== "media" && root.visible)
                MediaWidgetState.hide()
        }
    }

    Rectangle {
        id: card

        readonly property real fromW: PillState.pillWidth
        readonly property real fromH: PillState.pillHeight

        width: fromW + (root.panelW - fromW) * root.t
        height: fromH + (root.panelH - fromH) * root.t
        x: (root.width - width) / 2
        y: PillState.pillTop
        radius: fromH / 2 + (16 - fromH / 2) * root.t
        color: Theme.bg
        border.width: 1
        border.color: Qt.alpha(Theme.border, 0.6)
        clip: true

        Item {
            id: keyHost
            anchors.fill: parent
            focus: true
            Keys.onEscapePressed: MediaWidgetState.hide()
        }

        // content fades in during the second half of the morph
        Column {
            id: content
            anchors.fill: parent
            anchors.margins: 14
            opacity: Math.max(0, (root.t - 0.5) * 2)
            spacing: 12

            Row {
                id: header
                width: parent.width
                spacing: 14

                // track art, rounded by masking the image; a glyph while none is loaded
                Rectangle {
                    id: art
                    width: 64
                    height: 64
                    radius: 12
                    color: Qt.alpha(Theme.fg, 0.06)

                    Item {
                        id: artMask
                        anchors.fill: parent
                        visible: false
                        layer.enabled: true
                        Rectangle { anchors.fill: parent; radius: art.radius; color: "white" }
                    }

                    Image {
                        id: artImage
                        anchors.fill: parent
                        source: media.player?.trackArtUrl ?? ""
                        fillMode: Image.PreserveAspectCrop
                        visible: status === Image.Ready
                        layer.enabled: true
                        layer.effect: MultiEffect {
                            maskEnabled: true
                            maskSource: artMask
                        }
                    }
                    Text {
                        anchors.centerIn: parent
                        visible: artImage.status !== Image.Ready
                        text: "󰝚"
                        color: Qt.alpha(Theme.fg, 0.3)
                        font.family: Theme.fontFamily
                        font.pixelSize: 28
                    }
                }

                Column {
                    width: header.width - art.width - header.spacing
                    anchors.verticalCenter: art.verticalCenter
                    spacing: 4

                    MarqueeText {
                        width: parent.width
                        text: media.player?.trackTitle ?? ""
                        color: Theme.fg
                        font.family: Theme.fontFamily
                        font.pixelSize: 15
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
            }

            // progress with elapsed and remaining time under it
            Column {
                width: parent.width
                spacing: 6

                // progress line; click to seek, the hit area is taller than the line
                Item {
                    id: seek
                    width: parent.width
                    height: 4

                    Rectangle {
                        anchors.fill: parent
                        radius: 2
                        color: Qt.alpha(Theme.fg, 0.12)

                        Rectangle {
                            width: media.timed ? Math.min(media.pos / media.len, 1) * parent.width : 0
                            height: parent.height
                            radius: parent.radius
                            color: Theme.accent
                        }
                    }

                    MouseArea {
                        anchors.fill: parent
                        anchors.margins: -6
                        enabled: media.timed && (media.player?.canSeek ?? false)
                        onClicked: m => {
                            // the area reaches 6px past the track on each side
                            const frac = Math.min(Math.max((m.x - 6) / seek.width, 0), 1)
                            media.player.position = frac * media.len
                        }
                    }
                }

                Item {
                    width: parent.width
                    height: 12
                    visible: media.timed

                    Text {
                        anchors.left: parent.left
                        text: media.fmt(media.pos)
                        color: Qt.alpha(Theme.fg, 0.6)
                        font.family: Theme.fontFamily
                        font.pixelSize: 10
                    }
                    Text {
                        anchors.right: parent.right
                        text: "-" + media.fmt(Math.max(0, media.len - media.pos))
                        color: Qt.alpha(Theme.fg, 0.6)
                        font.family: Theme.fontFamily
                        font.pixelSize: 10
                    }
                }
            }

            component Btn: Text {
                id: btn
                property bool allowed: true
                signal tapped()
                y: (parent.height - height) / 2
                font.family: Theme.fontFamily
                font.pixelSize: 32
                color: !allowed ? Qt.alpha(Theme.fg, 0.25)
                     : ma.containsMouse ? Theme.accent : Theme.fg
                Behavior on color { ColorAnimation { duration: 120 } }

                MouseArea {
                    id: ma
                    anchors.fill: parent
                    anchors.margins: -8
                    hoverEnabled: true
                    onClicked: if (btn.allowed) btn.tapped()
                }
            }

            Row {
                id: controls
                height: 36
                anchors.horizontalCenter: parent.horizontalCenter
                spacing: 52

                Btn {
                    text: "󰒮"
                    allowed: media.player?.canGoPrevious ?? false
                    onTapped: media.player.previous()
                }
                Btn {
                    text: media.playing ? "󰏤" : "󰐊"
                    allowed: media.player?.canTogglePlaying ?? false
                    onTapped: media.player.togglePlaying()
                }
                Btn {
                    text: "󰒭"
                    allowed: media.player?.canGoNext ?? false
                    onTapped: media.player.next()
                }
            }
        }
    }
}
