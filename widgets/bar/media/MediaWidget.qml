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

    property bool lyricsOn: false

    // ── Lyrics state ───────────────────────────────────────────────────────
    property var lyrics: []
    property string lyricsKey: ""
    property string fetchKey: ""
    property var cache: ({})
    property string lyricStatus: ""
    property int lyricIdx: -1

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

    Timer {
        interval: 50
        repeat: true
        running: media.playing && root.lyricsOn && root.visible
        onTriggered: {
            root.livePos += 0.05
        }
    }

    IpcHandler {
        target: "media"
        function toggle(): void { WidgetLayout.toggle("media") }
        function show(): void { if (!WidgetLayout.shown("media")) WidgetLayout.toggle("media") }
        function hide(): void { if (WidgetLayout.shown("media")) WidgetLayout.toggle("media") }
        function kill(): void { media.kill() }
    }

    // ── Lyrics ─────────────────────────────────────────────────────────────

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

    function activeLineProgress() {
        if (lyricIdx < 0 || lyricIdx >= lyrics.length) return 0.0
        let currentLine = lyrics[lyricIdx]
        let nextLine = lyrics[lyricIdx + 1]
        
        if (!nextLine) return 1.0 
        
        let duration = nextLine.t - currentLine.t
        if (duration <= 0) return 0.0
        
        let elapsed = root.livePos - currentLine.t
        return Math.max(0.0, Math.min(1.0, elapsed / duration))
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

    Connections {
        target: media.player
        function onTrackTitleChanged() {
            root.lyricsKey = root.lyricsKey
            root.loadLyrics()
        }
    }

    Timer {
        id: lyricTimer
        interval: 50
        repeat: true
        running: root.lyricsOn && root.visible
        triggeredOnStart: true
        onTriggered: root.lyricIdx = root.lineAt(root.livePos)
    }

    // ── Custom Karaoke Fill Component (Fixed for Long Strings) ─────────────
    component KaraokeFillText: Item {
        id: kText
        property string text: ""
        property real progress: 0.0
        property color restingColor: Qt.alpha(Theme.fg, 0.35)
        property color activeColor: Theme.fg
        property int fontSize: 15
        property font customFont: Qt.font({ family: Theme.fontFamily, pixelSize: fontSize })

        implicitHeight: baseText.implicitHeight

        Text {
            id: baseText
            anchors.verticalCenter: parent.verticalCenter
            width: parent.width
            horizontalAlignment: Text.AlignHCenter
            elide: Text.ElideRight
            text: kText.text
            color: kText.restingColor
            font: kText.customFont
        }

        Item {
            id: fillMask
            anchors.verticalCenter: parent.verticalCenter
            anchors.left: parent.left
            width: baseText.width * Math.max(0.0, Math.min(1.0, kText.progress))
            height: baseText.height
            clip: true

            Text {
                id: activeText
                x: 0
                y: (fillMask.height - height) / 2
                width: baseText.width
                horizontalAlignment: Text.AlignHCenter
                elide: Text.ElideRight
                text: kText.text
                color: kText.activeColor
                font: kText.customFont
            }
        }
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
                visible: !root.lyricsOn
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
                visible: !root.lyricsOn
                width: parent.width
                height: 20
                text: media.player?.trackTitle ?? ""
                color: Theme.fg
                font.family: Theme.fontFamily
                font.pixelSize: 16
                // font.bold: true // Uncomment if MarqueeText supports bold property in your setup
            }

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

                    readonly property bool isActive: index === root.lyricIdx

                    KaraokeFillText {
                        anchors.centerIn: parent
                        width: parent.width
                        text: modelData.text
                        fontSize: isActive ? 15 : 14
                        customFont: Qt.font({ family: Theme.fontFamily, pixelSize: fontSize, bold: isActive })
                        progress: isActive ? root.activeLineProgress() : (index < root.lyricIdx ? 1.0 : 0.0)
                        restingColor: Qt.alpha(Theme.fg, 0.35)
                        activeColor: Theme.fg
                    }
                }
            }

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
