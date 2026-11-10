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

    property bool lyricsOn: false

    // ── Lyrics state ───────────────────────────────────────────────────────
    property var lyrics: []          // [{ t: seconds, text }]
    property string lyricsKey: ""    // artist|title the lyrics belong to
    property string fetchKey: ""     // key of the request in flight
    property var cache: ({})         // key -> parsed lyrics (may be empty)
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

    // the line shown in the title row while lyrics are on
    function currentLine() {
        if (lyrics.length === 0)
            return lyricStatus === "searching" ? "searching…"
                : lyricStatus === "none" ? "no synced lyrics" : ""
        return lyricIdx < 0 ? "…" : lyrics[lyricIdx].text
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
            root.lyricsKey = root.lyricsKey // keep bindings simple; reload below
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
    // the same dark card as the other corner widgets (todo, habits, usage),
    // with the cover rising from its top edge as a disc
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

        // the cover as a half-disc: centred on the card's top edge, so only its lower half shows
        Item {
            id: disc
            width: root.panelW
            height: root.panelW / 2
            clip: true

            Rectangle {
                id: face
                width: root.panelW
                height: root.panelW
                y: -height / 2
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

                // the layer stays on, so the mask is applied from the first frame
                // rather than only once the cover has loaded
                Image {
                    id: art
                    anchors.fill: parent
                    source: media.player?.trackArtUrl ?? ""
                    fillMode: Image.PreserveAspectCrop
                    asynchronous: true
                    sourceSize.width: root.panelW * 2
                    layer.enabled: true
                    layer.effect: MultiEffect {
                        maskEnabled: true
                        maskSource: faceMask
                    }
                }

                // hidden circle, used only to mask the cover
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

            // the spindle hole, half cut off by the card's top edge; it stays still while the disc turns
            Rectangle {
                anchors.horizontalCenter: parent.horizontalCenter
                y: -8
                width: 16
                height: 16
                radius: 8
                color: Theme.bg
                border.width: 3
                border.color: Qt.alpha(Theme.fg, 0.35)
            }
        }

        // a Column positions its children, so each centres with x rather than anchors
        Column {
            x: 24
            y: disc.height + 14
            width: card.width - 48
            spacing: 8

            // the wave the bar's indicator uses, here as a sign that a track is loaded
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

            // the artist, or the lyric before the current one
            Text {
                width: parent.width
                horizontalAlignment: Text.AlignHCenter
                elide: Text.ElideRight
                text: root.lyricsOn ? (root.lyrics[root.lyricIdx - 1]?.text ?? "") : media.artistText
                color: Qt.alpha(Theme.fg, 0.5)
                font.family: Theme.fontFamily
                font.pixelSize: 13
            }

            // the title, or the current lyric
            Text {
                width: parent.width
                horizontalAlignment: Text.AlignHCenter
                elide: Text.ElideRight
                text: root.lyricsOn ? root.currentLine() : (media.player?.trackTitle ?? "")
                color: Theme.fg
                font.family: Theme.fontFamily
                font.pixelSize: 16
                font.bold: true
            }

            // progress: a short centred track, so it reads as a marker rather than a bar
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

            // elapsed and total at rest; the transport and lyrics toggle on hover
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
