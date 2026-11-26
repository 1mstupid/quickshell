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
    // the cover fills the card, with a shadow rising from the bottom for the text
    Rectangle {
        id: card

        width: root.panelW
        height: root.panelW
        radius: 12
        color: Theme.altbg
        border.width: 1
        border.color: Qt.alpha(Theme.border, 0.6)

        HoverHandler { id: hover }

        // the cover, cut to the card's rounded corners by the mask below
        Item {
            id: art
            anchors.fill: parent
            layer.enabled: true
            layer.effect: MultiEffect {
                maskEnabled: true
                maskSource: cardMask
            }

            Image {
                anchors.fill: parent
                source: media.player?.trackArtUrl ?? ""
                fillMode: Image.PreserveAspectCrop
                asynchronous: true
                sourceSize.width: root.panelW * 2
            }

            Rectangle {
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.bottom: parent.bottom
                height: parent.height * 0.6
                gradient: Gradient {
                    GradientStop { position: 0.0; color: Qt.alpha(Theme.bg, 0) }
                    GradientStop { position: 1.0; color: Qt.alpha(Theme.bg, 0.9) }
                }
            }
        }

        // hidden rounded shape, used only to mask the cover
        Item {
            id: cardMask
            anchors.fill: parent
            visible: false
            layer.enabled: true

            Rectangle {
                anchors.fill: parent
                radius: card.radius
                color: "white"
            }
        }

        Column {
            x: 18
            anchors.bottom: parent.bottom
            anchors.bottomMargin: 16
            width: card.width - 36
            spacing: 4

            Text {
                width: parent.width
                elide: Text.ElideRight
                text: media.artistText
                color: Qt.alpha(Theme.fg, 0.6)
                font.family: Theme.fontFamily
                font.pixelSize: 12
            }

            MarqueeText {
                width: parent.width
                height: 20
                text: media.player?.trackTitle ?? ""
                color: Theme.fg
                font.family: Theme.fontFamily
                font.pixelSize: 16
                font.bold: true
            }

            Item {
                width: parent.width
                height: 2

                Rectangle {
                    anchors.fill: parent
                    radius: 1
                    color: Qt.alpha(Theme.fg, 0.2)
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
                height: 22

                Row {
                    anchors.left: parent.left
                    anchors.verticalCenter: parent.verticalCenter
                    visible: !hover.hovered
                    spacing: 0

                    Text {
                        text: media.fmt(root.livePos)
                        color: Theme.fg
                        font.family: Theme.fontFamilyAlt
                        font.pixelSize: 11
                        font.bold: true
                    }
                    Text {
                        visible: media.timed
                        text: " / " + media.fmt(media.len)
                        color: Qt.alpha(Theme.fg, 0.6)
                        font.family: Theme.fontFamilyAlt
                        font.pixelSize: 11
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
