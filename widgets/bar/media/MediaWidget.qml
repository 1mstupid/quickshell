import Quickshell
import Quickshell.Wayland
import Quickshell.Io
import QtQuick
import QtQuick.Effects
import "../../../services"

// Media widget on the wallpaper layer, bottom centre by default: a square card
// with the cover as a half-disc across its top, then artist, title and
// progress. Transport and the lyrics toggle appear while the pointer is over
// the card. The layout editor places it and switches it on and off;
// `qs ipc call media toggle` does the same. The bar's media wave opens the
// now-playing strip instead. Lyrics (LRCLIB) take the place of the artist and
// title while on. Only the card takes pointer events.
import Quickshell
import Quickshell.Wayland
import Quickshell.Io
import QtQuick
import QtQuick.Effects
import "../../../services"

// Media widget on the wallpaper layer, bottom centre by default: a square card
// with the cover as a half-disc across its top, then artist, title and
// progress. Transport and the lyrics toggle appear while the pointer is over
// the card. The layout editor places it and switches it on and off;
// `qs ipc call media toggle` does the same. The bar's media wave opens the
// now-playing strip instead. Lyrics (LRCLIB) take the place of the artist and
// title while on. Only the card takes pointer events.
PanelWindow {
    id: root

    screen: PillState.originScreen

    // a centre anchor leaves left and right unset, so the compositor centres the window
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

    // the card is square: the cover's half-disc is as wide as the card
    readonly property int panelW: 300
    // the cover disc is smaller than the card and lowered, so its flat top edge
    // sits inside the card's rounded corners instead of past them
    readonly property int discD: 300
    readonly property int discLower: 0  // the disc's centre, below the card's top edge

    property bool lyricsOn: false

    // ── Lyrics state ───────────────────────────────────────────────────────
    property var lyrics: []           // [{ t: seconds, text }]
    property string lyricsKey: ""    // artist|title the lyrics belong to
    property string fetchKey: ""     // key of the request in flight
    property var cache: ({})           // key -> parsed lyrics (may be empty)
    property string lyricStatus: ""  // "", "searching", "none"
    property int lyricIdx: -1

    // the position ticks only while the card shows
    MediaState {
        id: media
        active: root.visible
    }

    IpcHandler {
        target: "media"
        function toggle(): void { WidgetLayout.toggle("media") }
        function show(): void { if (!WidgetLayout.shown("media")) WidgetLayout.toggle("media") }
        function hide(): void { if (WidgetLayout.shown("media")) WidgetLayout.toggle("media") }
        function kill(): void { media.kill() }
    }

    // ── Lyrics ─────────────────────────────────────────────────────────────

    // LRC lines: "[mm:ss.xx] text"; the JSON's syncedLyrics holds them
    function parseLrc(json) {
        let synced = ""
        try {
            synced = JSON.parse(json).syncedLyrics ?? ""
        } catch (e) {
            return []
        }
        const out = []
        for (const line of synced.split("\n")) {
            const m = line.match(/^\[(\d+):(\d+(?:\.\d+)?)\]\s?(.*)$/)
            if (m)
                out.push({ t: parseInt(m[1]) * 60 + parseFloat(m[2]), text: m[3] })
        }
        return out
    }

    // index of the last line whose time has passed, or -1 before the first
    function lineAt(pos) {
        let i = -1
        for (let k = 0; k < lyrics.length; k++) {
            if (lyrics[k].t <= pos)
                i = k
            else
                break
        }
        return i
    }

    function loadLyrics() {
        const title = media.player?.trackTitle ?? ""
        const artist = media.artistText
        if (!lyricsOn || title === "") {
            lyricStatus = ""
            return
        }
        const key = artist + "|" + title
        if (key === lyricsKey)
            return
        lyricsKey = key
        if (cache[key] !== undefined) {
            lyrics = cache[key]
            lyricStatus = lyrics.length ? "" : "none"
            return
        }
        lyrics = []
        lyricStatus = "searching"
        fetchKey = key

        const args = ["curl", "-sG", "--max-time", "8", "https://lrclib.net/api/get",
            "--data-urlencode", "track_name=" + title,
            "--data-urlencode", "artist_name=" + artist]
        if (media.len > 0)
            args.push("--data-urlencode", "duration=" + Math.round(media.len))

        fetchProc.running = false
        fetchProc.command = args
        fetchProc.running = true
    }

    Process {
        id: fetchProc
        stdout: StdioCollector {
            onStreamFinished: {
                const parsed = root.parseLrc(text)
                const c = Object.assign({}, root.cache)
                c[root.fetchKey] = parsed
                root.cache = c
                if (root.fetchKey === root.lyricsKey) {
                    root.lyrics = parsed
                    root.lyricStatus = parsed.length ? "" : "none"
                }
            }
        }
    }

    onLyricsOnChanged: loadLyrics()

    // a new track in the same player
    Connections {
        target: media.player
        function onTrackTitleChanged() {
            root.lyricsKey = root.lyricsKey
            root.loadLyrics()
        }
    }

    // follows the player position
    Timer {
        interval: 250
        repeat: true
        running: root.lyricsOn && root.visible
        triggeredOnStart: true
        onTriggered: root.lyricIdx = root.lineAt(media.player?.position ?? 0)
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

        // the cover disc container with a top-corner rounding mask matching the card
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

                // the disc turns while the track plays and holds its angle on pause
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

        // a Column positions its children
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

            // --- Normal Mode: Artist Text ---
            Text {
                visible: !root.lyricsOn
                width: parent.width
                horizontalAlignment: Text.AlignHCenter
                elide: Text.ElideRight
                text: media.artistText
                color: Qt.alpha(Theme.fg, 0.5)
                font.family: Theme.fontFamily
                font.pixelSize: 13
            }

            // --- Normal Mode: Track Title ---
            Text {
                visible: !root.lyricsOn
                width: parent.width
                horizontalAlignment: Text.AlignHCenter
                elide: Text.ElideRight
                text: media.player?.trackTitle ?? ""
                color: Theme.fg
                font.family: Theme.fontFamily
                font.pixelSize: 16
                font.bold: true
            }

            // --- Lyrics Mode: Spotify-Style Vertical ListView ---
            ListView {
                id: lyricsView
                visible: root.lyricsOn && root.lyrics.length > 0
                width: parent.width
                height: 48
                clip: true
                model: root.lyrics

                currentIndex: root.lyricIdx
                preferredHighlightBegin: height / 2 - 12
                preferredHighlightEnd: height / 2 + 12
                highlightRangeMode: ListView.ApplyRange
                highlightMoveDuration: 200

                delegate: Item {
                    required property int index
                    required property var modelData

                    width: lyricsView.width
                    height: 24

                    // Use MarqueeText for the active line, standard Text for inactive lines
                    Loader {
                        anchors.fill: parent
                        sourceComponent: index === root.lyricIdx ? activeLyricComp : normalLyricComp

                        Component {
                            id: activeLyricComp
                            MarqueeText {
                                anchors.verticalCenter: parent.verticalCenter
                                width: parent.width
                                text: modelData.text
                                color: Theme.fg
                                font.family: Theme.fontFamily
                                font.pixelSize: 15
                                // font.bold: true // If your MarqueeText supports bold property
                            }
                        }

                        Component {
                            id: normalLyricComp
                            Text {
                                anchors.verticalCenter: parent.verticalCenter
                                width: parent.width
                                horizontalAlignment: Text.AlignHCenter
                                elide: Text.ElideRight
                                text: modelData.text
                                font.family: Theme.fontFamily
                                font.pixelSize: 15
                                color: Qt.alpha(Theme.fg, 0.35)
                            }
                        }
                    }
                }
            }

            // --- Lyrics Mode: Status / Loading Message ---
            Text {
                visible: root.lyricsOn && (root.lyricStatus !== "" || root.lyrics.length === 0)
                width: parent.width
                horizontalAlignment: Text.AlignHCenter
                text: root.lyricStatus === "searching" ? "searching…" : root.lyricStatus === "none" ? "no synced lyrics" : ""
                color: Qt.alpha(Theme.fg, 0.5)
                font.family: Theme.fontFamily
                font.pixelSize: 13
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
                    width: parent.width * (media.timed ? Math.min(1, media.pos / media.len) : 0)
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
                        text: media.fmt(media.pos)
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

                    Rectangle {
                        id: lyricsPill
                        anchors.verticalCenter: parent.verticalCenter
                        width: 44
                        height: 20
                        radius: 6
                        color: root.lyricsOn ? Qt.alpha(Theme.fg, 0.25)
                               : lyricsMa.containsMouse ? Qt.alpha(Theme.fg, 0.16)
                               : Qt.alpha(Theme.fg, 0.08)
                        Behavior on color { ColorAnimation { duration: 120 } }

                        Text {
                            anchors.centerIn: parent
                            text: "lyrics"
                            color: Theme.fg
                            font.family: Theme.fontFamily
                            font.pixelSize: 11
                        }
                        MouseArea {
                            id: lyricsMa
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root.lyricsOn = !root.lyricsOn
                        }
                    }
                }
            }
        }
    }
}
