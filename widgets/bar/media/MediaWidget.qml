import Quickshell
import Quickshell.Wayland
import Quickshell.Io
import QtQuick
import QtQuick.Effects
import "../../../services"
import "../../notch"

// Media widget. It morphs out of the bar pill, like the other panels. Opened by
// the wave (or `qs ipc call media toggle`), closed by Escape, and closed when the
// track stops. The lyrics toggle shows synced lyrics from LRCLIB.
PanelWindow {
    id: root

    screen: PillState.originScreen
    visible: false

    anchors {
        top: true
        left: true
        right: true
    }
    implicitHeight: PillState.pillTop + maxPanelH + 12

    color: "transparent"
    exclusionMode: ExclusionMode.Ignore

    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: root.visible ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None
    WlrLayershell.namespace: "quickshell-media"

    readonly property int panelW: 340
    // collapsed: pad 14 + art 56 + gap + progress 22 + gap + controls 36 + pad 14
    // expanded adds the lyrics block
    readonly property int collapsedH: 164
    readonly property int lyricsH: 84
    readonly property int maxPanelH: collapsedH + lyricsH + 12

    property bool lyricsOn: false
    property int panelH: lyricsOn ? collapsedH + lyricsH + 12 : collapsedH
    Behavior on panelH {
        NumberAnimation { duration: 250; easing.type: Easing.OutCubic }
    }

    // 0 = the bar pill, 1 = the full widget
    property real t: 0

    // ── Lyrics state ───────────────────────────────────────────────────────
    property var lyrics: []          // [{ t: seconds, text }]
    property string lyricsKey: ""    // artist|title the lyrics belong to
    property string fetchKey: ""     // key of the request in flight
    property var cache: ({})         // key -> parsed lyrics (may be empty)
    property string lyricStatus: ""  // "", "searching", "none"
    property int lyricIdx: -1

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
    mask: Region { item: outline }

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

    // follows the player position, faster than MediaState's one-second tick
    Timer {
        interval: 250
        repeat: true
        running: root.lyricsOn && root.visible
        triggeredOnStart: true
        onTriggered: root.lyricIdx = root.lineAt(media.player?.position ?? 0)
    }

    // ── Card ───────────────────────────────────────────────────────────────

    // the outline is a notch, drawn behind the card and sized to it
    Notch {
        id: outline
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
            spacing: 10
            opacity: Math.max(0, (root.t - 0.5) * 2)

            // ── Header: art, title, artist, player, lyrics toggle ──────────
            Item {
                id: header
                width: parent.width
                height: 56

                // artwork, rounded by masking the image; a glyph while none is loaded
                Rectangle {
                    id: art
                    width: 56
                    height: 56
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
                        font.pixelSize: 26
                    }
                }

                // lyrics toggle, on the right of the header
                Rectangle {
                    id: lyricsPill
                    anchors.right: parent.right
                    anchors.top: parent.top
                    width: 50
                    height: 20
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

                Column {
                    anchors.left: art.right
                    anchors.leftMargin: 12
                    anchors.right: parent.right
                    anchors.rightMargin: 0
                    anchors.verticalCenter: art.verticalCenter
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
                    Text {
                        width: parent.width
                        visible: text !== ""
                        elide: Text.ElideRight
                        text: media.player?.identity ?? ""
                        color: Qt.alpha(Theme.fg, 0.35)
                        font.family: Theme.fontFamilyAlt
                        font.pixelSize: 10
                    }
                }
            }

            // ── Progress with elapsed and remaining time ───────────────────
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

            // ── Transport controls ─────────────────────────────────────────
            component Btn: Text {
                id: btn
                property bool allowed: true
                signal tapped()
                y: (parent.height - height) / 2
                font.family: Theme.fontFamily
                font.pixelSize: 30
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

            // ── Lyrics: previous, current, next; hidden while collapsed ────
            Item {
                id: lyricsBlock
                width: parent.width
                height: root.lyricsOn ? root.lyricsH : 0
                visible: root.lyricsOn
                clip: true

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
                    width: parent.width
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
}
