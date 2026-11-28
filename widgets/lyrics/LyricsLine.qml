import QtQuick
import "../../services"
import "../bar/media/LyricsMath.js" as LM

// One line of the lyrics stack. Its place, size and tilt follow from `d`, its distance from
// the middle, so lines glide into place. The words fill as they are sung, and a diamond hops
// from word to word over the tune, landing on each as it starts. Ad libs in brackets are
// smaller and raised; a second line at the same moment is a small row above. A line that is
// still being sung when the next one starts is held just above it (LyricsMath.js does the
// timing). Adapted from sekaipop's LyricsLine.qml (GPL-3.0); see the README.
//
// The line is centred on (cx, cy + pose.y * zoom).
Item {
    id: line

    property string text: ""
    property real lineStart: 0
    property real lineEnd: 0
    property real t: 0
    property int index: 0
    property int curIndex: -1
    property bool playing: false
    property real d: 0
    // a line that is only there (a message, not a lyric): no singing, no marker
    property bool still: false
    // the whole line lights when it starts: no word hops, no marker
    property bool lineOnly: false
    // word timing from an enhanced lyrics file; empty for most
    property var marks: []
    // a voice that sings along with the line
    property string bgText: ""
    property real bgStart: 0
    property real bgEnd: 0
    // how much the next line takes this one over, the same for the line before, and when
    // that line has been sung by
    property real rush: 0
    property real prevRush: 0
    property real prevEnd: 0
    property real maxW: 680
    property int px: 38
    // the widget's size: the poses' offsets are in pixels at 1
    property real zoom: 1
    property real cx: 0
    property real cy: 0

    // dimmed while the music is paused
    property real dim: line.playing ? 1 : 0.62
    Behavior on dim { NumberAnimation { duration: 320 } }

    // ===== taken over / taking over =====
    readonly property real held: (line.rush > 0 && !line.still && !line.blank) ? LM.hold(line.t, line.lineEnd, line.rush) : 0
    readonly property real heldAbove: (line.prevRush > 0 && !line.still) ? LM.hold(line.t, line.prevEnd, line.prevRush) : 0
    readonly property real entryRush: (line.still || line.index <= 0) ? 0 : LM.rushOf(LM.overrun(line.prevEnd, line.lineStart))
    readonly property real land: (line.isCur && line.entryRush > 0) ? LM.landing(line.t - line.lineStart, line.entryRush) : 0
    readonly property var pose: LM.takeover(line.d, line.held)

    readonly property var toks: LM.tokens(line.text)
    readonly property bool blank: line.toks.length === 0 && !line.still
    readonly property var sp: LM.spansFor(line.toks, line.lineStart, Math.max(0.1, line.lineEnd - line.lineStart), line.marks)
    // the words the marker hops over (not the ad libs), and their times
    readonly property var mainIdx: LM.mainIndexes(line.toks)
    readonly property var mainSp: {
        const out = []
        for (let i = 0; i < line.mainIdx.length; i++)
            out.push(line.sp[line.mainIdx[i]])
        return out
    }

    // the voice that sings along
    readonly property var bgToks: line.bgText !== "" ? LM.tokens(line.bgText) : []
    readonly property bool hasBg: line.bgToks.length > 0 && !line.still && !line.blank
    readonly property int bgPx: Math.max(14, Math.round(line.px * 0.5))
    readonly property var bgSp: LM.spans(line.bgToks, line.bgStart, Math.max(0.2, Math.max(line.bgEnd, line.lineEnd) - line.bgStart))
    readonly property real bgIn: !line.hasBg ? 0
        : (line.index < line.curIndex ? 1 : (line.isCur ? Math.max(0, Math.min(1, (line.t - line.bgStart + 0.12) / 0.3)) : 0))

    readonly property bool isCur: !line.still && line.index === line.curIndex
    // a line that was taken over: the next one has begun and this one is still being sung
    readonly property bool carried: !line.still && line.index < line.curIndex && line.t >= line.lineStart && line.t < line.lineEnd
    readonly property bool singing: line.isCur || line.carried
    readonly property bool litOn: !line.still && (line.index === line.curIndex || line.index === line.curIndex - 1 || line.carried)

    // `kmAny`: the word the marker is on by the clock alone; `km`: the same, only while sung
    readonly property int kmAny: LM.wordAt(line.mainSp, line.t)
    readonly property int km: line.singing ? line.kmAny : -1
    readonly property real hopP: LM.hop(line.mainSp, line.kmAny, line.t)
    readonly property real pad: Math.round(line.px * 0.95)
    // line only: how lit the whole line is, a quick fade-in from its start
    readonly property real wholeLit: Math.max(0, Math.min(1, (line.t - line.lineStart) / 0.18))
    readonly property real bgWholeLit: Math.max(0, Math.min(1, (line.t - line.bgStart) / 0.18))

    readonly property bool done: !line.still && line.t >= line.lineEnd

    x: line.cx
    y: line.cy + line.pose.y * line.zoom
    width: 0
    height: 0

    // the middle of word i, in the line's own coordinates
    function center(i) {
        const it = reps.itemAt(i)
        return it ? it.x + it.gapW + it.fullW / 2 : 0
    }

    // the diamonds fly off the words of the tune when the marker lands on one
    onKmChanged: {
        if (!line.lineOnly && line.singing && line.playing && line.km >= 0) {
            puff.x = line.center(line.mainIdx[line.km])
            puff.y = line.pad + line.px * 0.2
            puff.fire()
        }
    }

    // a line that was taken over has just been sung: a few diamonds off its last word
    onDoneChanged: {
        if (!line.lineOnly && line.done && line.playing && line.index < line.curIndex
                && line.t - line.lineEnd < 0.35 && line.mainIdx.length > 0) {
            signoff.x = line.center(line.mainIdx[line.mainIdx.length - 1])
            signoff.y = line.pad + line.px * 0.2
            signoff.fire()
        }
    }

    Item {
        id: holder

        width: line.blank ? line.px * 3.4 : Math.max(1, row.implicitWidth)
        height: line.blank ? line.px * 1.4 : row.implicitHeight + 2 * line.pad
        x: -width / 2
        y: -height / 2
        transformOrigin: Item.Center
        scale: line.pose.scale * (1 + 0.06 * line.land) * LM.fit(row.implicitWidth, line.maxW)
        rotation: line.pose.rot
        opacity: line.pose.opacity * line.dim
        visible: opacity > 0.01

        Row {
            id: row
            y: line.pad
            visible: !line.blank

            Repeater {
                id: reps
                model: line.toks

                delegate: Item {
                    id: cell

                    required property var modelData
                    required property int index

                    // an ad lib: smaller, raised and tilted
                    readonly property bool ad: cell.modelData.adlib === true
                    readonly property real sizeK: cell.ad ? 0.68 : 1
                    readonly property real fullW: Math.round(w.implicitWidth * cell.sizeK)
                    readonly property real gapW: cell.modelData.gap ? Math.round(line.px * 0.3) : 0
                    readonly property var span: line.sp[cell.index]
                    readonly property real sungV: (line.litOn && cell.span !== undefined)
                        ? (line.lineOnly ? line.wholeLit : LM.sung(cell.span, line.t)) : 0
                    // the wave before the line starts: word i hops a little after the one before it
                    readonly property real stagger: 0.13
                    readonly property real wave: Math.max(0, Math.min(1,
                        (1 - line.d) * (1 + cell.stagger * (line.toks.length - 1)) - cell.index * cell.stagger))
                    readonly property real lift: (!line.lineOnly && line.d > -0.01 && line.d < 1) ? Math.sin(Math.PI * cell.wave) : 0
                    readonly property real hitV: (!line.lineOnly && line.singing && line.playing) ? LM.hit(line.sp, cell.index, line.t) : 0

                    width: cell.gapW + cell.fullW
                    height: w.implicitHeight

                    LyricsWord {
                        id: w
                        x: cell.gapW - (w.implicitWidth - cell.fullW) / 2
                        y: -line.px * 0.24 * cell.lift + 3 * cell.hitV - (cell.ad ? line.px * 0.1 : 0)
                        text: cell.modelData.s
                        pixelSize: line.px
                        withFill: line.litOn
                        sung: cell.sungV
                        litColor: cell.ad ? Theme.alert : Theme.primary
                        scale: cell.sizeK * (1 + 0.11 * cell.lift)
                        rotation: cell.ad ? -3 : 0
                        transformOrigin: Item.Bottom

                        transform: Scale {
                            origin.x: w.width / 2
                            origin.y: w.height
                            xScale: 1 + 0.07 * cell.hitV
                            yScale: 1 - 0.15 * cell.hitV
                        }
                    }
                }
            }
        }

        // the bouncing marker: it hops over the words of the tune only
        Item {
            id: marker

            readonly property int hereM: Math.max(0, line.kmAny)
            readonly property int thereM: Math.min(marker.hereM + 1, Math.max(0, line.mainIdx.length - 1))
            readonly property int here: line.mainIdx.length > 0 ? line.mainIdx[marker.hereM] : 0
            readonly property int there: line.mainIdx.length > 0 ? line.mainIdx[marker.thereM] : 0
            // the words' places are known once the row has been laid out
            readonly property bool laidOut: row.implicitWidth > 0
            readonly property real ax: laidOut ? line.center(marker.here) : 0
            readonly property real bx: laidOut ? line.center(marker.there) : 0
            readonly property real arch: LM.arch(line.hopP)
            // lower under a row that sings along, and lower while a held line is above this one
            readonly property real archK: (line.hasBg ? 0.5 : 0.85) * (1 - 0.5 * line.heldAbove)
            // grows in when its line starts and shrinks away when the singing ends
            property real presence: line.singing ? 1 : 0

            Behavior on presence {
                NumberAnimation {
                    duration: line.singing ? 200 : 260
                    easing.type: line.singing ? Easing.OutBack : Easing.InCubic
                }
            }

            visible: !line.blank && !line.lineOnly && marker.presence > 0.01
            x: marker.ax + (marker.bx - marker.ax) * line.hopP
            y: line.pad - line.px * 0.16 - marker.arch * line.px * marker.archK
            rotation: 180 * line.hopP
            scale: (1 + 0.28 * marker.arch) * Math.max(0, marker.presence)

            DiamondDot {
                anchors.centerIn: parent
                lit: true
                litColor: Theme.primary
                lineColor: Theme.border
                size: Math.round(line.px * 0.3)
            }
        }

        Burst {
            id: puff
            count: 6
            radius: line.px * 0.95
            size: Math.max(6, Math.round(line.px * 0.2))
            colors: [Theme.primary, Theme.fg, Theme.alert]
        }

        // the sign-off of a line that was taken over
        Burst {
            id: signoff
            count: 8
            radius: line.px * 1.15
            size: Math.max(6, Math.round(line.px * 0.22))
            colors: [Theme.alert, Theme.fg, Theme.primary]
        }

        // a voice that sings along: a small row just above the words
        Row {
            id: bgRow
            visible: line.hasBg && line.bgIn > 0.01
            opacity: line.bgIn
            spacing: Math.round(line.bgPx * 0.3)
            x: Math.round((row.implicitWidth - bgRow.width) / 2)
            y: Math.round(line.pad - bgRow.height * 0.8 + line.px * 0.22 + (1 - line.bgIn) * 8)

            Repeater {
                model: line.bgToks

                delegate: LyricsWord {
                    required property var modelData
                    required property int index

                    text: modelData.s
                    pixelSize: line.bgPx
                    withFill: true
                    litColor: Theme.alert
                    sung: line.lineOnly ? line.bgWholeLit
                        : (line.bgSp[index] ? LM.sung(line.bgSp[index], line.t) : 0)
                }
            }
        }

        // a gap in the singing: three diamonds that light one by one, then shrink away
        Row {
            visible: line.blank
            anchors.centerIn: parent
            spacing: Math.round(line.px * 0.42)

            Repeater {
                model: 3

                delegate: Item {
                    id: bead

                    required property int index

                    readonly property real room: Math.max(0.5, line.lineEnd - line.lineStart)
                    readonly property real leaving: line.isCur ? Math.max(0, Math.min(1, (line.lineEnd - line.t) / 0.5)) : 1
                    readonly property real breath: (line.isCur && line.playing) ? 1 + 0.14 * Math.sin(line.t * 5 + bead.index * 1.1) : 1

                    width: Math.round(line.px * 0.3)
                    height: width
                    scale: Math.max(0.001, bead.leaving * bead.breath)

                    DiamondDot {
                        anchors.centerIn: parent
                        size: bead.width
                        lit: line.isCur && line.t >= line.lineStart + (bead.index + 1) * bead.room / 4.2
                        litColor: Theme.primary
                        lineColor: Theme.border
                    }
                }
            }
        }
    }
}
