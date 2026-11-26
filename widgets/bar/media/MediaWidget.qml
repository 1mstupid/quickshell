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

    Component.onCompleted: {
        WidgetLayout.register("media", root);
        cavaConfigWriter.running = true;
    }

    // cava listens only while the card is up and a track plays, so it is not left running
    property bool cavaReady: false

    readonly property int panelW: 300

    property real livePos: 0.0
    property var audioBars: [10, 10, 10, 10, 10, 10, 10, 10, 10, 10, 10, 10, 10, 10, 10, 10, 10, 10, 10, 10]

    MediaState {
        id: media
        active: root.visible
    }

    Connections {
        target: media
        function onPosChanged() {
            root.livePos = media.pos
        }
        function onPlayingChanged() {
            waveCanvas.requestPaint()
        }
    }

    IpcHandler {
        target: "media"
        function toggle(): void { WidgetLayout.toggle("media") }
        function show(): void { if (!WidgetLayout.shown("media")) WidgetLayout.toggle("media") }
        function hide(): void { if (WidgetLayout.shown("media")) WidgetLayout.toggle("media") }
        function kill(): void { media.kill() }
    }

    // ── 1. Write temp config file for Cava ─────────────────────────────────
    Process {
        id: cavaConfigWriter
        command: [
            "sh", "-c",
            "printf '[general]\nbars = 20\nframerate = 60\n[input]\nmethod = pipewire\nsource = auto\n[output]\nmethod = raw\ndata_format = ascii\nascii_max_range = 100\n' > /tmp/quickshell_cava_config"
        ]
        onExited: root.cavaReady = true
    }

    // ── 2. Run Cava using the generated config file ────────────────────────
    Process {
        id: cavaProcess
        running: root.cavaReady && root.visible && media.playing
        command: ["cava", "-p", "/tmp/quickshell_cava_config"]

        stdout: SplitParser {
            onRead: data => {
                var trimmed = data.trim();
                if (trimmed.length > 0) {
                    var parts = trimmed.split(";");
                    if (parts.length >= 20) {
                        var newBars = [];
                        for (var i = 0; i < 20; i++) {
                            var val = parseInt(parts[i]) || 0;
                            newBars.push(val);
                        }
                        root.audioBars = newBars;
                        waveCanvas.requestPaint();
                    }
                }
            }
        }
    }

    // ── Card ───────────────────────────────────────────────────────────────
    Rectangle {
        id: card

        width: root.panelW
        height: root.panelW
        radius: 12
        color: Theme.altbg
        border.width: 1
        border.color: Qt.alpha(Theme.border, 0.6)

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

            // fades into the theme background, so the text sits on the card's own colour
            Rectangle {
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.bottom: parent.bottom
                height: parent.height * 0.7
                gradient: Gradient {
                    GradientStop { position: 0.0; color: Qt.alpha(Theme.bg, 0) }
                    GradientStop { position: 0.5; color: Qt.alpha(Theme.bg, 0.6) }
                    GradientStop { position: 1.0; color: Qt.alpha(Theme.bg, 0.95) }
                }
            }
        }

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

        // ── Anchored, Symmetrically Mirrored Wave Visualizer ─────────────────
        Item {
            id: waveContainer
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.leftMargin: 18
            anchors.rightMargin: 18
            anchors.verticalCenter: parent.verticalCenter
            height: 55
            z: 2
            visible: media.present

            Canvas {
                id: waveCanvas
                anchors.fill: parent

                onPaint: {
                    var ctx = getContext("2d");
                    ctx.clearRect(0, 0, width, height);

                    if (!media.playing) {
                        ctx.beginPath();
                        ctx.strokeStyle = Qt.alpha(Theme.fg, 0.25);
                        ctx.lineWidth = 2;
                        ctx.moveTo(0, height / 2);
                        ctx.lineTo(width, height / 2);
                        ctx.stroke();
                        return;
                    }

                    ctx.beginPath();
                    ctx.strokeStyle = Qt.alpha(Theme.fg, 0.9);
                    ctx.lineWidth = 2.5;
                    ctx.lineCap = "round";
                    ctx.lineJoin = "round";

                    // Mirror the cava bars array for a centered, symmetric wave layout
                    var rawBars = root.audioBars;
                    var bars = rawBars.slice().reverse().concat(rawBars);

                    var step = width / (bars.length - 1);
                    var centerY = height / 2;

                    for (var i = 0; i < bars.length; i++) {
                        var x = i * step;
                        var normalizedVal = (bars[i] / 100.0) * (height * 0.42);
                        var y = centerY + (i % 2 === 0 ? -1 : 1) * normalizedVal;

                        if (i === 0) {
                            ctx.moveTo(x, y);
                        } else {
                            var prevX = (i - 1) * step;
                            var prevNormalized = (bars[i - 1] / 100.0) * (height * 0.42);
                            var prevY = centerY + ((i - 1) % 2 === 0 ? -1 : 1) * prevNormalized;
                            
                            var xc = (prevX + x) / 2;
                            var yc = (prevY + y) / 2;
                            ctx.quadraticCurveTo(prevX, prevY, xc, yc);
                        }
                    }
                    ctx.stroke();
                }
            }
        }

        // ── Metadata & Progress Bar ─────────────────────────────────────────
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
            }
        }
    }
}
