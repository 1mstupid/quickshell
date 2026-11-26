import Quickshell
import Quickshell.Wayland
import Quickshell.Io
import QtQuick
import "../../services"
import "../bar/media"
import "../bar/media/LyricsMath.js" as LM

// The desktop lyrics: the words of the song that is playing, sung along on the wallpaper.
// No card: each line is a sticker (LyricsWord.qml) lying straight on the picture. The line
// being sung is big in the middle; the one before has slid up and faded; the one to come
// waits below, small and tilted. A few moments before a line starts the stack climbs to it.
//
// The words come from lrclib.net (curl), as the media card used to fetch them, and are read
// by LyricsMath.js. The clock is read from the player four times a second and runs smoothly
// in between (LyricsMath.observe), so a player that answers late does not make the words early
// then late. A plain lyrics file only says when a LINE starts, so the words of a line share its
// time by syllable. Adapted from sekaipop's lyrics widget (GPL-3.0); see the README.
//
// Placed by the layout editor like the other corner widgets. It is off until shown:
//   qs ipc call lyrics toggle        (or: quickshell ipc call lyrics toggle)
//   quickshell ipc call lyrics nudge 250    (the words 250 ms earlier; -250 for later)
//   quickshell ipc call lyrics nudgeReset
PanelWindow {
    id: root

    screen: PillState.originScreen

    // placed like the media card: its corner or edge comes from the layout (WidgetLayout)
    anchors {
        left: WidgetLayout.hasLeft("lyrics")
        right: WidgetLayout.hasRight("lyrics")
        top: WidgetLayout.hasTop("lyrics")
        bottom: WidgetLayout.hasBottom("lyrics")
    }
    margins {
        left: WidgetLayout.insetX("lyrics")
        right: WidgetLayout.insetX("lyrics")
        top: WidgetLayout.insetY("lyrics")
        bottom: WidgetLayout.insetY("lyrics")
    }

    // the card's design size, in the shell's scale
    readonly property real k: Theme.autoScale
    readonly property int cardW: Math.round(720 * root.k)
    readonly property int cardH: Math.round(244 * root.k)
    implicitWidth: root.cardW
    implicitHeight: root.cardH

    color: "transparent"
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.layer: WlrLayer.Background
    WlrLayershell.namespace: "quickshell-lyrics"
    mask: Region { item: card }

    visible: WidgetLayout.shown("lyrics") && media.present && !Overview.open
    Component.onCompleted: WidgetLayout.register("lyrics", root)

    // ===== the player =====
    MediaState {
        id: media
        active: root.visible
    }

    readonly property bool playing: media.playing
    readonly property string trackTitle: media.player?.trackTitle ?? ""
    // a new song is a new title or artist (the length arriving later does not count)
    readonly property string trackSig: root.trackTitle + "␟" + media.artistText

    onTrackSigChanged: {
        root.clk = LM.clockReset(0, Date.now())
        root.lastPolled = -1
        root.stalePolls = 0
        root.poll()
        root.loadLyrics()
    }

    onPlayingChanged: {
        // freeze the clock where it was on pause, or restart it from there
        const now = Date.now()
        root.clk = LM.clockReset(LM.estimate(root.clk, now, !root.playing), now)
        root.lastPolled = -1
        root.stalePolls = 0
        root.poll()
    }

    onVisibleChanged: {
        if (visible) {
            root.loadLyrics()
            root.lastPolled = -1
            root.stalePolls = 0
            root.poll()
        }
    }

    // ===== the words =====
    property var lines: []
    property string lyricsKey: ""
    // the lookup that is running, and the one waiting for it to stop; each run has a number,
    // printed with its output, so a result is matched to its own song whatever the timing
    property int runSeq: 0
    property var runKeys: ({})
    property var pendingArgs: null
    property string pendingKey: ""
    property var cache: ({})
    // "" (nothing to say), "searching", or "none" (the service has no synced words)
    property string status: ""
    // this session's nudge, in ms: the words are moved earlier by it
    property int nudgeMs: 0

    function loadLyrics() {
        const title = root.trackTitle
        if (!root.visible || title === "") {
            if (title === "") {
                root.lines = []
                root.status = ""
                root.lyricsKey = ""
            }
            return
        }
        const artist = media.artistText
        const key = LM.trackKey(artist, title, media.len)
        if (key === root.lyricsKey)
            return
        root.lyricsKey = key

        if (root.cache[key] !== undefined) {
            root.lines = root.cache[key]
            root.status = root.lines.length ? "" : "none"
            return
        }

        root.lines = []
        root.status = "searching"

        const cands = LM.candidates(artist, title)
        const qArtist = cands.length > 0 ? cands[0].artist : artist
        const qTitle = cands.length > 0 ? cands[0].title : title
        const args = ["curl", "-sG", "--max-time", "8", "https://lrclib.net/api/get",
            "--data-urlencode", "track_name=" + qTitle,
            "--data-urlencode", "artist_name=" + qArtist]
        if (media.len > 0)
            args.push("--data-urlencode", "duration=" + Math.round(media.len))

        // one lookup at a time: a newer song stops the running one, and starts once it has exited
        root.pendingArgs = args
        root.pendingKey = key
        if (fetchProc.running)
            fetchProc.running = false
        else
            root.startPending()
    }

    function startPending() {
        if (root.pendingArgs === null)
            return
        root.runSeq = root.runSeq + 1
        const keys = Object.assign({}, root.runKeys)
        keys[root.runSeq] = root.pendingKey
        root.runKeys = keys
        // the script prints the run's number last, after curl's output
        fetchProc.command = ["sh", "-c", 'curl "$@"; echo; echo RUN:' + root.runSeq, "sh"]
            .concat(root.pendingArgs.slice(1))
        root.pendingArgs = null
        fetchProc.running = true
    }

    Process {
        id: fetchProc
        onExited: root.startPending()
        stdout: StdioCollector {
            onStreamFinished: {
                // without the run's number at the end, the output was cut off: nothing to keep
                const m = /\nRUN:(\d+)\s*$/.exec(text)
                if (m === null)
                    return
                const key = root.runKeys[Number(m[1])]
                let parsed = null
                try {
                    parsed = LM.foldEchoes(LM.parseLrc(JSON.parse(text.slice(0, m.index)).syncedLyrics ?? ""))
                } catch (e) {
                    parsed = null
                }
                // a lookup that failed or was cut short is not kept, so the song is asked for again
                if (parsed !== null) {
                    const c = Object.assign({}, root.cache)
                    c[key] = parsed
                    root.cache = c
                }
                if (key === root.lyricsKey) {
                    if (parsed === null) {
                        root.lyricsKey = ""
                        root.status = "none"
                    } else {
                        root.lines = parsed
                        root.status = parsed.length ? "" : "none"
                    }
                }
            }
        }
    }

    // ===== the clock =====
    property var clk: LM.clockReset(0, 0)
    property real now: Date.now()
    property real lastPolled: -1
    property int stalePolls: 0

    function poll() {
        const p = media.player
        if (!p)
            return
        const polled = Number(p.position)
        if (!isFinite(polled))
            return
        const trust = LM.pollTrust(root.lastPolled, polled, root.stalePolls, root.playing)
        root.lastPolled = polled
        root.stalePolls = trust.stale
        if (trust.use)
            root.clk = LM.observe(root.clk, polled, Date.now(), root.playing)
        root.now = Date.now()
    }

    // read the player while the widget is shown
    Timer {
        interval: 250
        repeat: true
        running: root.visible
        onTriggered: root.poll()
    }

    // redraw every frame while the words are moving
    Timer {
        interval: 33
        repeat: true
        running: root.visible && root.playing && root.lines.length > 0
        onTriggered: root.now = Date.now()
    }

    // the player's position is never newer than the sound, which takes a moment to leave the
    // speakers, so the words are shown this much early (on top of the nudge)
    readonly property real playerLead: 0.2
    readonly property real clockT: LM.estimate(root.clk, root.now, root.playing) + root.playerLead + root.nudgeMs / 1000

    // ===== the stack =====
    // how long before a line starts the stack begins to climb to it
    readonly property real lead: 0.45
    readonly property real rate: LM.songRate(root.lines)
    readonly property int curIndex: LM.lineIndexAt(root.lines, root.clockT)
    readonly property real nextRush: root.takeAfter(root.curIndex)
    readonly property real cursorV: LM.cursor(root.lines, root.clockT, root.lead, root.nextRush)
    readonly property int base: Math.round(root.cursorV)

    // when line i has been sung by: its start plus the time its words take, never past the next start
    function endOf(i) {
        const l = root.lines[i]
        if (!l)
            return 0
        const next = i + 1 < root.lines.length ? root.lines[i + 1].t : Infinity
        const room = next - l.t
        if (l.text === "")
            return l.t + (isFinite(room) ? room : 4)
        const known = (l.end !== undefined && l.end > l.t) ? l.end - l.t : undefined
        return l.t + LM.sungSpan(l.text, room, root.rate, known)
    }

    // when the voice that sings along with line i has been sung by
    function bgEndOf(i) {
        const l = root.lines[i]
        if (!l || !l.bg)
            return 0
        return Math.max(root.endOf(i), l.bg.t + LM.sungSpan(l.bg.text, Infinity, root.rate))
    }

    // how much line i is held (0 .. 1): still being sung when the stack starts to climb away
    function rushAfter(i) {
        if (i < 0 || i + 1 >= root.lines.length)
            return 0
        const l = root.lines[i]
        if (l.text === "")
            return 0
        return LM.rushOf(LM.overrun(root.endOf(i), LM.leaveAt(l.t, root.lines[i + 1].t, root.lead)))
    }

    // how much the line after line i takes it over (0 .. 1)
    function takeAfter(i) {
        if (i < 0 || i + 1 >= root.lines.length || root.lines[i].text === "")
            return 0
        return LM.rushOf(LM.overrun(root.endOf(i), root.lines[i + 1].t))
    }

    // what the middle says when there are no lines to sing
    readonly property string message: root.lines.length > 0 ? ""
        : root.status === "searching" ? "looking for the words…"
        : root.status === "none" ? "no synced lyrics" : ""

    // the small tag under the words: what is playing, and the nudge when there is one
    readonly property string tag: {
        const a = media.artistText
        let s = a !== "" ? (root.trackTitle + " - " + a) : root.trackTitle
        if (s.length > 56)
            s = s.slice(0, 55) + "…"
        if (root.nudgeMs !== 0)
            s += "   nudge " + (root.nudgeMs / 1000).toFixed(1) + " s"
        return s
    }

    IpcHandler {
        target: "lyrics"
        function toggle(): void { WidgetLayout.toggle("lyrics") }
        function show(): void { if (!WidgetLayout.shown("lyrics")) WidgetLayout.toggle("lyrics") }
        function hide(): void { if (WidgetLayout.shown("lyrics")) WidgetLayout.toggle("lyrics") }
        function nudge(ms: int): void { root.nudgeMs += ms }
        function nudgeReset(): void { root.nudgeMs = 0 }
    }

    Item {
        id: card
        width: root.cardW
        height: root.cardH

        readonly property real midY: 112 * root.k

        // one line per lyric, but only the lines near the middle are built
        Repeater {
            model: root.lines.length

            delegate: Loader {
                id: slot

                required property int index

                active: Math.abs(slot.index - root.base) <= 2

                sourceComponent: LyricsLine {
                    text: root.lines[slot.index] ? root.lines[slot.index].text : ""
                    index: slot.index
                    curIndex: root.curIndex
                    lineStart: root.lines[slot.index] ? root.lines[slot.index].t : 0
                    lineEnd: root.endOf(slot.index)
                    rush: root.rushAfter(slot.index)
                    prevRush: root.rushAfter(slot.index - 1)
                    prevEnd: slot.index > 0 ? root.endOf(slot.index - 1) : 0
                    marks: (root.lines[slot.index] && root.lines[slot.index].marks) ? root.lines[slot.index].marks : []
                    bgText: (root.lines[slot.index] && root.lines[slot.index].bg) ? root.lines[slot.index].bg.text : ""
                    bgStart: (root.lines[slot.index] && root.lines[slot.index].bg) ? root.lines[slot.index].bg.t : 0
                    bgEnd: root.bgEndOf(slot.index)
                    t: root.clockT
                    d: slot.index - root.cursorV
                    playing: root.playing
                    px: Math.round(34 * root.k)
                    maxW: card.width - 40
                    cx: card.width / 2
                    cy: card.midY
                }
            }
        }

        // a message in the middle when there is nothing to sing
        LyricsLine {
            visible: root.message !== ""
            still: true
            text: root.message
            px: Math.round(28 * root.k)
            d: 0
            playing: true
            maxW: card.width - 40
            cx: card.width / 2
            cy: card.midY
        }

        // what is playing, small, under the words
        Text {
            text: root.tag
            x: Math.round((card.width - width) / 2)
            y: card.height - height - 2
            color: Qt.alpha(Theme.fg, 0.8)
            font.family: Theme.fontFamilySans
            font.pixelSize: Math.round(13 * root.k)
            style: Text.Outline
            styleColor: Theme.bg
        }
    }
}
