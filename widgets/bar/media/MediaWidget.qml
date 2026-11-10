import Quickshell
import Quickshell.Wayland
import Quickshell.Io
import QtQuick
import QtQuick.Effects
import "../../../services"

// Media widget on the wallpaper layer, bottom centre by default: cover art,
// title and artist, and the transport controls. It shows while a track is
// loaded and the widget is on. The layout editor places it and switches it on
// and off; `qs ipc call media toggle` does the same. The bar's media wave opens
// the now-playing strip instead. The lyrics toggle opens a block of synced
// lyrics (LRCLIB) above the card, which grows upward so the controls stay under
// the pointer. Only the card takes pointer events.
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

    // always tall enough for the lyrics, so toggling them never resizes the
    // window; the card grows inside it and the mask keeps the rest clickable
    implicitHeight: mainH + lyricsH

    color: "transparent"
    exclusionMode: ExclusionMode.Ignore

    WlrLayershell.layer: WlrLayer.Background
    WlrLayershell.namespace: "quickshell-media"

    mask: Region { item: card }

    visible: WidgetLayout.shown("media") && media.present && !Overview.open

    Component.onCompleted: WidgetLayout.register("media", root)

    readonly property int panelW: 340
    // the art is a square the height of the main section
    readonly property int mainH: 120
    readonly property int lyricsH: 76
    readonly property int pad: 14

    property bool lyricsOn: false
    property real shownH: lyricsOn ? mainH + lyricsH : mainH
    Behavior on shownH {
        NumberAnimation { duration: 250; easing.type: Easing.OutCubic }
    }

    // ── Lyrics state ───────────────────────────────────────────────────────
    property var lyrics: []          // [{ t: seconds, text }]
    property string lyricsKey: ""    // artist|title the lyrics belong to
    property string fetchKey: ""     // key of the request in flight
    property var cache: ({})         // key -> parsed lyrics (may be empty)
    property string lyricStatus: ""  // "", "searching", "none"
    property int lyricIdx: -1

    // nothing here reads the one-second position tick; the lyrics timer below
    // reads the player directly
    MediaState {
        id: media
        active: false
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
        signal tapped()
        anchors.verticalCenter: parent.verticalCenter
        font.family: Theme.fontFamily
        font.pixelSize: 20
        color: !allowed ? Qt.alpha(Theme.fg, 0.25)
             : ma.containsMouse ? Theme.accent : Theme.fg
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
        height: root.shownH
        x: (root.width - width) / 2
        y: root.height - height
        radius: 16
        color: Qt.alpha(Theme.bg, 0.92)
        border.width: 1
        border.color: Qt.alpha(Theme.border, 0.6)
        clip: true

        // art, text and controls, pinned to the bottom so they stay put when the
        // lyrics open above them
        Item {
            id: main
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            height: root.mainH

            // artwork, flush with the card inside its border. Only the left
            // corners are rounded; the image is masked to the same shape, and a
            // glyph shows while none is loaded.
            Rectangle {
                id: art
                x: 1
                y: 1
                width: root.mainH - 2
                height: root.mainH - 2
                topLeftRadius: card.radius - 1
                bottomLeftRadius: card.radius - 1
                color: Qt.alpha(Theme.fg, 0.06)

                Item {
                    id: artMask
                    anchors.fill: parent
                    visible: false
                    layer.enabled: true
                    Rectangle {
                        anchors.fill: parent
                        topLeftRadius: art.topLeftRadius
                        bottomLeftRadius: art.bottomLeftRadius
                        color: "white"
                    }
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
                    font.pixelSize: 30
                }
            }

            // title and artist on top, controls at the bottom right
            Item {
                id: side
                anchors.left: art.right
                anchors.leftMargin: root.pad
                anchors.right: parent.right
                anchors.rightMargin: root.pad
                anchors.top: parent.top
                anchors.topMargin: root.pad
                anchors.bottom: parent.bottom
                anchors.bottomMargin: root.pad

                Column {
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.top: parent.top
                    spacing: 3

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
                        font.pixelSize: 13
                    }
                }

                Row {
                    id: controls
                    anchors.right: parent.right
                    anchors.bottom: parent.bottom
                    spacing: 10

                    Rectangle {
                        id: lyricsPill
                        anchors.verticalCenter: parent.verticalCenter
                        width: 50
                        height: 22
                        radius: 7
                        color: root.lyricsOn ? Qt.alpha(Theme.accent, 0.25)
                             : lyricsMa.containsMouse ? Qt.alpha(Theme.fg, 0.14)
                             : Qt.alpha(Theme.fg, 0.08)
                        Behavior on color { ColorAnimation { duration: 120 } }

                        Text {
                            anchors.centerIn: parent
                            text: "lyrics"
                            color: root.lyricsOn ? Theme.accent : Theme.fg
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

                    Btn {
                        text: "󰒮"
                        allowed: media.player?.canGoPrevious ?? false
                        onTapped: media.player.previous()
                    }

                    // the one filled control, like START on the focus card
                    Rectangle {
                        id: playBtn
                        readonly property bool allowed: media.player?.canTogglePlaying ?? false
                        anchors.verticalCenter: parent.verticalCenter
                        width: 40
                        height: 40
                        radius: 20
                        color: !allowed ? Qt.alpha(Theme.fg, 0.15)
                             : playMa.containsMouse ? Qt.lighter(Theme.accent, 1.1) : Theme.accent
                        Behavior on color { ColorAnimation { duration: 120 } }

                        Text {
                            anchors.centerIn: parent
                            text: media.playing ? "󰏤" : "󰐊"
                            color: Theme.bg
                            font.family: Theme.fontFamily
                            font.pixelSize: 22
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

        // ── Lyrics: previous, current, next. Sits on top of the main section,
        // so it is clipped away while the card is short and slides in as it grows.
        Item {
            id: lyricsBlock
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.bottom: main.top
            height: root.lyricsH
            opacity: root.lyricsOn ? 1 : 0
            visible: opacity > 0
            Behavior on opacity { NumberAnimation { duration: 150 } }

            // status line while there are no lines to show
            Text {
                anchors.centerIn: parent
                visible: root.lyrics.length === 0
                text: root.lyricStatus === "searching" ? "searching…"
                    : root.lyricStatus === "none" ? "no synced lyrics" : ""
                color: Qt.alpha(Theme.fg, 0.4)
                font.family: Theme.fontFamily
                font.pixelSize: 11
            }

            Column {
                anchors.centerIn: parent
                width: parent.width - 2 * root.pad
                spacing: 4
                visible: root.lyrics.length > 0

                Text {
                    width: parent.width
                    horizontalAlignment: Text.AlignHCenter
                    wrapMode: Text.WordWrap
                    maximumLineCount: 1
                    elide: Text.ElideRight
                    text: root.lyrics[root.lyricIdx - 1]?.text ?? ""
                    color: Qt.alpha(Theme.fg, 0.3)
                    font.family: Theme.fontFamily
                    font.pixelSize: 11
                }
                Text {
                    width: parent.width
                    horizontalAlignment: Text.AlignHCenter
                    wrapMode: Text.WordWrap
                    maximumLineCount: 2
                    elide: Text.ElideRight
                    text: root.lyricIdx < 0 ? "…" : (root.lyrics[root.lyricIdx]?.text ?? "")
                    color: Theme.fg
                    font.family: Theme.fontFamily
                    font.pixelSize: 13
                    font.bold: true
                }
                Text {
                    width: parent.width
                    horizontalAlignment: Text.AlignHCenter
                    wrapMode: Text.WordWrap
                    maximumLineCount: 1
                    elide: Text.ElideRight
                    text: root.lyrics[root.lyricIdx + 1]?.text ?? ""
                    color: Qt.alpha(Theme.fg, 0.3)
                    font.family: Theme.fontFamily
                    font.pixelSize: 11
                }
            }
        }
    }
}
