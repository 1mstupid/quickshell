import Quickshell
import Quickshell.Wayland
import Quickshell.Io
import QtQuick
import QtQuick.Effects
import "../../../services"

PanelWindow {
    id: root

    screen: PillState.originScreen

    anchors {
        left: WidgetLayout.hasLeft("media")
        right: WidgetLayout.hasRight("media")
        top: WidgetLayout.hasTop("media")
        bottom: WidgetLayout.hasBottom("media")
    }
    margins {
        left: WidgetLayout.insetX("media")
        right: WidgetLayout.insetX("media")
        top: WidgetLayout.insetY("media")
        bottom: WidgetLayout.insetY("media")
    }
    implicitWidth: panelW
    implicitHeight: panelW

    color: "transparent"
    exclusionMode: ExclusionMode.Ignore

    WlrLayershell.layer: WlrLayer.Background
    WlrLayershell.namespace: "quickshell-media"

    mask: Region { item: card }

    visible: WidgetLayout.shown("media") && media.present && !Overview.open

    Component.onCompleted: WidgetLayout.register("media", root)

    readonly property int panelW: 300
    readonly property int discD: 300
    readonly property int discLower: 0

    // Local smooth position tracker for live updating during playback
    property real livePos: 0.0

    MediaState {
        id: media
        active: root.visible
    }

    Connections {
        target: media
        function onPosChanged() {
            root.livePos = media.pos
        }
    }

    IpcHandler {
        target: "media"
        function toggle(): void { WidgetLayout.toggle("media") }
        function show(): void { if (!WidgetLayout.shown("media")) WidgetLayout.toggle("media") }
        function hide(): void { if (WidgetLayout.shown("media")) WidgetLayout.toggle("media") }
        function kill(): void { media.kill() }
    }

    // ── Transport buttons ──────────────────────────────────────────────────
    component Btn: Text {
        id: btn
        property bool allowed: true
        property color tint: Theme.fg
        signal tapped()
        anchors.verticalCenter: parent.verticalCenter
        font.family: Theme.fontFamily
        font.pixelSize: 20
        color: !allowed ? Qt.alpha(tint, 0.25)
               : ma.containsMouse ? Theme.accent : tint
        Behavior on color { ColorAnimation { duration: 120 } }

        MouseArea {
            id: ma
            anchors.fill: parent
            anchors.margins: -8
            hoverEnabled: true
            cursorShape: btn.allowed ? Qt.PointingHandCursor : Qt.ArrowCursor
            onClicked: if (btn.allowed) btn.tapped()
        }
    }

    // ── Card ───────────────────────────────────────────────────────────────
    Rectangle {
        id: card

        width: root.panelW
        height: root.panelW
        radius: 12
        color: Qt.alpha(Theme.bg, 0.92)
        border.width: 1
        border.color: Qt.alpha(Theme.border, 0.6)
        clip: true

        HoverHandler { id: hover }

        Item {
            id: disc
            width: root.panelW
            height: root.discLower + root.discD / 2

            layer.enabled: true
            layer.effect: MultiEffect {
                maskEnabled: true
                maskSource: discMask
            }

            Item {
                id: discMask
                anchors.fill: parent
                visible: false
                layer.enabled: true

                Rectangle {
                    anchors.fill: parent
                    radius: card.radius
                    color: "white"
                }
            }

            Rectangle {
                id: face
                width: root.discD
                height: root.discD
                x: (root.panelW - width) / 2
                y: root.discLower - height / 2
                radius: width / 2
                color: Theme.altbg

                NumberAnimation on rotation {
                    running: media.playing
                    loops: Animation.Infinite
                    from: face.rotation
                    to: face.rotation + 360
                    duration: 12000
                }

                Image {
                    id: art
                    anchors.fill: parent
                    source: media.player?.trackArtUrl ?? ""
                    fillMode: Image.PreserveAspectCrop
                    asynchronous: true
                    sourceSize.width: root.discD * 2
                    layer.enabled: true
                    layer.effect: MultiEffect {
                        maskEnabled: true
                        maskSource: faceMask
                    }
                }

                Item {
                    id: faceMask
                    anchors.fill: parent
                    visible: false
                    layer.enabled: true

                    Rectangle {
                        anchors.fill: parent
                        radius: width / 2
                        color: "white"
                    }
                }
            }

            Rectangle {
                anchors.horizontalCenter: parent.horizontalCenter
                y: root.discLower - 8
                width: 16
                height: 16
                radius: 8
                color: Theme.bg
                border.width: 3
                border.color: Qt.alpha(Theme.fg, 0.35)
            }
        }

        Column {
            x: 24
            y: disc.height + 14
            width: card.width - 48
            spacing: 8

            Row {
                x: (parent.width - width) / 2
                height: 14
                spacing: 2

                Repeater {
                    model: 5

                    Rectangle {
                        id: waveBar
                        required property int index
                        y: (parent.height - height) / 2
                        width: 2
                        height: 6
                        radius: 1
                        color: Qt.alpha(Theme.fg, 0.4)

                        SequentialAnimation on height {
                            running: media.playing
                            loops: Animation.Infinite
                            NumberAnimation { to: 13; duration: 280 + waveBar.index * 60; easing.type: Easing.InOutSine }
                            NumberAnimation { to: 4; duration: 280 + waveBar.index * 60; easing.type: Easing.InOutSine }
                        }
                    }
                }
            }

            Text {
                width: parent.width
                horizontalAlignment: Text.AlignHCenter
                elide: Text.ElideRight
                text: media.artistText
                color: Qt.alpha(Theme.fg, 0.5)
                font.family: Theme.fontFamily
                font.pixelSize: 13
            }

            // --- Normal Mode: Track Title (Upgraded to MarqueeText) ---
            MarqueeText {
                width: parent.width
                height: 20
                text: media.player?.trackTitle ?? ""
                color: Theme.fg
                font.family: Theme.fontFamily
                font.pixelSize: 16
            }

            Item {
                x: (parent.width - width) / 2
                width: 40
                height: 2

                Rectangle {
                    anchors.fill: parent
                    radius: 1
                    color: Qt.alpha(Theme.fg, 0.15)
                }
                Rectangle {
                    height: parent.height
                    radius: 1
                    color: Theme.fg
                    width: parent.width * (media.timed ? Math.min(1, root.livePos / media.len) : 0)
                }
            }

            Item {
                width: parent.width
                height: 24

                Row {
                    anchors.centerIn: parent
                    visible: !hover.hovered
                    spacing: 0

                    Text {
                        text: media.fmt(root.livePos)
                        color: Theme.fg
                        font.family: Theme.fontFamilyAlt
                        font.pixelSize: 15
                        font.bold: true
                    }
                    Text {
                        visible: media.timed
                        text: " / " + media.fmt(media.len)
                        color: Qt.alpha(Theme.fg, 0.4)
                        font.family: Theme.fontFamilyAlt
                        font.pixelSize: 15
                    }
                }

                Row {
                    anchors.centerIn: parent
                    visible: hover.hovered
                    spacing: 20

                    Btn {
                        text: "󰒮"
                        allowed: media.player?.canGoPrevious ?? false
                        onTapped: media.player.previous()
                    }

                    Rectangle {
                        id: playBtn
                        readonly property bool allowed: media.player?.canTogglePlaying ?? false
                        anchors.verticalCenter: parent.verticalCenter
                        width: 34
                        height: 34
                        radius: 17
                        color: !allowed ? Qt.alpha(Theme.fg, 0.25)
                               : playMa.containsMouse ? Theme.accent : Theme.fg
                        Behavior on color { ColorAnimation { duration: 120 } }

                        Text {
                            anchors.centerIn: parent
                            text: media.playing ? "󰏤" : "󰐊"
                            color: Theme.bg
                            font.family: Theme.fontFamily
                            font.pixelSize: 18
                        }
                        MouseArea {
                            id: playMa
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: playBtn.allowed ? Qt.PointingHandCursor : Qt.ArrowCursor
                            onClicked: if (playBtn.allowed) media.player.togglePlaying()
                        }
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
}
