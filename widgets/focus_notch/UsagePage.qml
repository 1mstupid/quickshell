import QtQuick
import "../../services"

// The Usage page of the focus notch: time per app for today, this week or this
// month. Today is charted by hour with a strip of sessions under the chart; the
// other spans are charted by day. It is the old usage dashboard, fitted to the
// notch's panel: the stats sit on one line and the most used list is shorter.
Item {
    id: usage

    // ── Geometry ───────────────────────────────────────────────────────────
    readonly property int pad: 18
    // the grey panels' padding
    readonly property int inset: 8
    readonly property int bodyTop: 60
    readonly property int chartPanelW: 380
    readonly property int chartW: chartPanelW - 2 * inset
    readonly property int listPanelW: width - 2 * pad - chartPanelW - 16
    readonly property int bodyPanelH: height - bodyTop - 10
    readonly property int bodyH: bodyPanelH - 2 * inset

    // the legend, the bars, then the column labels and the strip under them
    readonly property int legendRowH: 24
    readonly property int legendH: legendRows.length > 0 ? legendRows.length * legendRowH - 10 : 0
    readonly property int barsTop: legendH + 8
    readonly property int chartH: Math.max(40, bodyH - barsTop - 30)
    readonly property int labelsTop: barsTop + chartH + 4
    readonly property int stripTop: labelsTop + 16

    readonly property color surface: Qt.alpha(Theme.fg, 0.06)

    // ── Span ───────────────────────────────────────────────────────────────
    // "day" for today, "week" for this calendar week, "month" for this calendar month
    property string period: "day"
    readonly property var periodTabs: [
        { key: "day", name: "Day" },
        { key: "week", name: "Week" },
        { key: "month", name: "Month" }
    ]

    // the day keys in the span, oldest first. The week runs Sunday to Saturday and
    // the month runs from its first day to its last, so future days are empty.
    readonly property var spanKeys: {
        AppUsage.revision
        const now = new Date()
        const y = now.getFullYear()
        const m = now.getMonth()
        const key = d => Qt.formatDate(d, "yyyy-MM-dd")
        if (period === "day")
            return [key(now)]
        if (period === "week") {
            const sunday = now.getDate() - now.getDay()
            return [0, 1, 2, 3, 4, 5, 6].map(i => key(new Date(y, m, sunday + i)))
        }
        const count = new Date(y, m + 1, 0).getDate()
        return Array.from({ length: count }, (_, i) => key(new Date(y, m, i + 1)))
    }
    // one column per hour for today, otherwise one per day
    readonly property int columns: period === "day" ? 24 : spanKeys.length
    readonly property real slotW: chartW / columns
    readonly property real barW: Math.min(slotW - 4, 24)

    // ── Data ───────────────────────────────────────────────────────────────
    // seconds per app across the span, most used first
    readonly property var allApps: {
        const sums = {}
        for (const k of spanKeys)
            for (const r of AppUsage.totals(k, AppUsage.revision))
                sums[r.app] = (sums[r.app] ?? 0) + r.sec
        return Object.keys(sums)
            .map(a => ({ app: a, sec: sums[a] }))
            .sort((a, b) => b.sec - a.sec)
    }

    // sessions across the span, in day order then time order
    readonly property var sessions: {
        const out = []
        for (const k of spanKeys)
            out.push(...AppUsage.sessionsOf(k, AppUsage.revision))
        return out
    }

    // five rows fit the list panel at its height
    readonly property var listRows: allApps.slice(0, 5)
    readonly property real totalSec: allApps.reduce((s, r) => s + r.sec, 0)
    readonly property real topSec: listRows.length > 0 ? listRows[0].sec : 1

    // categories across the span, most used first: the legend and the stacking order
    readonly property var categoryOrder: {
        const sums = {}
        for (const r of allApps) {
            const c = AppUsage.categoryOf(r.app)
            sums[c] = (sums[c] ?? 0) + r.sec
        }
        return Object.keys(sums).sort((a, b) => sums[b] - sums[a])
    }

    // the legend, split into rows. The widths are estimates from the name
    // lengths, so the rows are a little generous rather than cramped.
    readonly property var legendRows: {
        const rows = []
        let row = []
        let w = 0
        for (const c of categoryOrder) {
            const cw = 14 + c.length * 7 + 12
            if (w + cw > chartW && row.length > 0) {
                rows.push(row)
                row = []
                w = 0
            }
            row.push(c)
            w += cw
        }
        if (row.length > 0)
            rows.push(row)
        return rows
    }

    // the apps behind one column: an hour of today, or a whole day
    function columnApps(i) {
        if (period === "day")
            return AppUsage.hoursOf(spanKeys[0], AppUsage.revision)[i] ?? {}
        const sums = {}
        for (const r of AppUsage.totals(spanKeys[i], AppUsage.revision))
            sums[r.app] = r.sec
        return sums
    }

    function columnTotal(i) {
        const a = columnApps(i)
        return Object.keys(a).reduce((s, k) => s + a[k], 0)
    }

    // the busiest column sets the scale in the day view, so a quiet day still fills
    // the chart. Week and month use a fixed 24 hours for a full bar.
    readonly property real peakSec: Math.max(60, ...Array.from({ length: columns }, (_, i) => columnTotal(i)))
    readonly property real scaleSec: period === "day" ? peakSec : 86400

    // the named categories share an accent ramp spread across the whole range,
    // so 2 categories and 8 both use the full brightness range. "Other" is grey.
    function colorFor(c) {
        if (c === "Other")
            return Qt.alpha(Theme.fg, 0.45)
        const named = categoryOrder.filter(x => x !== "Other")
        const n = named.length
        const i = Math.max(0, named.indexOf(c))
        const step = n > 1 ? 0.7 / (n - 1) : 0
        return Qt.alpha(Theme.accent, 1 - i * step)
    }

    // one column's bar, split by category from the bottom up
    function segmentsFor(i) {
        const scale = chartH / scaleSec
        const a = columnApps(i)
        const sums = {}
        for (const app of Object.keys(a)) {
            const c = AppUsage.categoryOf(app)
            sums[c] = (sums[c] ?? 0) + a[app]
        }
        const out = []
        let bottom = 0
        for (const c of categoryOrder) {
            const sec = sums[c] ?? 0
            if (sec <= 0)
                continue
            const size = sec * scale
            out.push({ bottom: bottom, size: size, color: colorFor(c) })
            bottom += size
        }
        return out
    }

    function colX(i) {
        return i * slotW + (slotW - barW) / 2
    }

    // hour of the day for today, weekday for the week, day of month for the month
    function labelFor(i) {
        if (period === "day")
            return i % 6 === 0 ? String(i).padStart(2, "0") : ""
        const k = spanKeys[i]
        if (period === "week") {
            const p = k.split("-").map(Number)
            return Qt.formatDate(new Date(p[0], p[1] - 1, p[2]), "ddd")
        }
        // the first of the month, then every fifth day
        const d = Number(k.slice(8))
        return d === 1 || d % 5 === 0 ? String(d) : ""
    }

    // local midnight of today, in ms, for placing sessions on the strip
    function dayStartMs() {
        const n = new Date()
        return new Date(n.getFullYear(), n.getMonth(), n.getDate()).getTime()
    }

    // today's strip: every session, in its category colour
    readonly property var stripItems: {
        if (period !== "day")
            return []
        return AppUsage.sessionsOf(spanKeys[0], AppUsage.revision)
            .map(s => ({ start: s.start, end: s.end, color: colorFor(AppUsage.categoryOf(s.app)) }))
    }

    // ── Stats ──────────────────────────────────────────────────────────────
    readonly property string firstUse: sessions.length > 0
        ? Qt.formatDateTime(new Date(sessions[0].start), period === "day" ? "HH:mm" : "ddd HH:mm")
        : "—"
    readonly property real longestSec: sessions.reduce((m, s) => Math.max(m, (s.end - s.start) / 1000), 0)
    readonly property string longestText: longestSec > 0
        ? Math.max(1, Math.round(longestSec / 60)) + " min" : "—"
    readonly property string notifyText: String(spanKeys.reduce(
        (s, k) => s + AppUsage.notificationsOf(k, AppUsage.revision), 0))
    readonly property string pomodoroText: String(spanKeys.reduce(
        (s, k) => s + AppUsage.pomodoros(k, AppUsage.revision), 0))

    // ── Header: the span's switch and the total ────────────────────────────
    // the same segmented switch as Work's, at the same place
    Rectangle {
        id: periodSwitch
        x: usage.pad
        y: 0
        width: periodRow.width + 4
        height: 24
        radius: 7
        color: Qt.alpha(Theme.fg, 0.08)

        Row {
            id: periodRow
            x: 2
            y: 2
            spacing: 2

            Repeater {
                model: usage.periodTabs

                Rectangle {
                    id: periodSeg
                    required property var modelData
                    readonly property bool on: usage.period === periodSeg.modelData.key

                    width: periodName.implicitWidth + 20
                    height: 20
                    radius: 5
                    color: on ? Qt.alpha(Theme.fg, 0.14)
                         : periodMouse.containsMouse ? Qt.alpha(Theme.fg, 0.06) : "transparent"
                    Behavior on color { ColorAnimation { duration: 120 } }

                    Text {
                        id: periodName
                        anchors.centerIn: parent
                        text: periodSeg.modelData.name
                        color: periodSeg.on ? Theme.fg : Qt.alpha(Theme.fg, 0.6)
                        font.family: Theme.fontFamilySans
                        font.pixelSize: 11
                    }
                    MouseArea {
                        id: periodMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: usage.period = periodSeg.modelData.key
                    }
                }
            }
        }
    }

    Text {
        anchors.right: parent.right
        anchors.rightMargin: usage.pad
        anchors.verticalCenter: periodSwitch.verticalCenter
        text: AppUsage.fmt(usage.totalSec)
        color: Theme.fg
        font.family: Theme.fontFamilyDisplay
        font.pixelSize: 16
        font.bold: true
    }

    // the stats on one line under the header
    Row {
        x: usage.pad
        y: 32
        spacing: 18

        Repeater {
            model: [
                { label: "FIRST USE", value: usage.firstUse },
                { label: "NOTIFICATIONS", value: usage.notifyText },
                { label: "LONGEST", value: usage.longestText },
                { label: "POMODOROS", value: usage.pomodoroText }
            ]

            Row {
                id: stat
                required property var modelData
                spacing: 6

                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: stat.modelData.label
                    color: Qt.alpha(Theme.fg, 0.6)
                    font.family: Theme.fontFamilyAlt
                    font.pixelSize: 9
                    font.letterSpacing: 1
                }
                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: stat.modelData.value
                    color: Theme.fg
                    font.family: Theme.fontFamilyAlt
                    font.pixelSize: 11
                    font.bold: true
                }
            }
        }
    }

    // ── Body: the chart, then the most used apps ───────────────────────────
    Row {
        x: usage.pad
        y: usage.bodyTop
        spacing: 16

        // the chart's grey panel
        Item {
            width: usage.chartPanelW
            height: usage.bodyPanelH

            Rectangle {
                anchors.fill: parent
                radius: 10
                color: usage.surface
            }

            Item {
                x: usage.inset
                y: usage.inset
                width: usage.chartW
                height: usage.bodyH

                // legend, wrapped to fit the chart's width
                Column {
                    width: usage.chartW
                    height: usage.legendH
                    spacing: 10

                    Repeater {
                        model: usage.legendRows

                        Row {
                            id: legendRow
                            required property var modelData
                            spacing: 12

                            Repeater {
                                model: legendRow.modelData

                                Row {
                                    id: entry
                                    required property var modelData
                                    spacing: 6

                                    Rectangle {
                                        y: 3
                                        width: 8
                                        height: 8
                                        radius: 4
                                        color: usage.colorFor(entry.modelData)
                                    }
                                    Text {
                                        text: entry.modelData
                                        color: Qt.alpha(Theme.fg, 0.85)
                                        font.family: Theme.fontFamilyAlt
                                        font.pixelSize: 10
                                    }
                                }
                            }
                        }
                    }
                }

                Item {
                    id: bars
                    y: usage.barsTop
                    width: parent.width
                    height: usage.chartH

                    Repeater {
                        model: usage.columns

                        Item {
                            id: col
                            required property int index
                            x: usage.colX(col.index)
                            width: usage.barW
                            height: bars.height

                            Repeater {
                                model: usage.segmentsFor(col.index)

                                Rectangle {
                                    id: piece
                                    required property var modelData
                                    width: col.width
                                    y: col.height - piece.modelData.bottom - piece.modelData.size
                                    height: piece.modelData.size
                                    color: piece.modelData.color
                                }
                            }

                            // the empty stage: an outline the height of the peak column
                            Rectangle {
                                anchors.fill: parent
                                radius: 3
                                color: "transparent"
                                border.width: 1
                                border.color: Qt.alpha(Theme.fg, 0.35)
                            }
                        }
                    }
                }

                // column labels under the bars
                Repeater {
                    model: usage.columns

                    Text {
                        id: label
                        required property int index
                        x: label.index * usage.slotW
                        y: usage.labelsTop
                        width: usage.slotW
                        horizontalAlignment: Text.AlignHCenter
                        text: usage.labelFor(label.index)
                        color: Qt.alpha(Theme.fg, 0.85)
                        font.family: Theme.fontFamilyAlt
                        font.pixelSize: 9
                    }
                }

                // today's strip of sessions, for today only
                Rectangle {
                    visible: usage.period === "day"
                    y: usage.stripTop
                    width: usage.chartW
                    height: 6
                    radius: 3
                    color: Qt.alpha(Theme.fg, 0.06)

                    Repeater {
                        model: usage.stripItems

                        Rectangle {
                            id: block
                            required property var modelData
                            x: (block.modelData.start - usage.dayStartMs()) / 86400000 * usage.chartW
                            width: Math.max(2, (block.modelData.end - block.modelData.start) / 86400000 * usage.chartW)
                            height: 6
                            radius: 3
                            color: block.modelData.color
                        }
                    }
                }
            }
        }

        // the list's grey panel
        Item {
            width: usage.listPanelW
            height: usage.bodyPanelH

            Rectangle {
                anchors.fill: parent
                radius: 10
                color: usage.surface
            }

            Column {
                x: usage.inset
                y: usage.inset
                width: usage.listPanelW - 2 * usage.inset
                spacing: 4

                Text {
                    text: "MOST USED"
                    color: Qt.alpha(Theme.fg, 0.6)
                    font.family: Theme.fontFamilyAlt
                    font.pixelSize: 9
                    font.letterSpacing: 1
                }

                Repeater {
                    model: usage.listRows

                    Item {
                        id: row
                        required property var modelData
                        width: parent.width
                        height: 18

                        Text {
                            anchors.left: parent.left
                            anchors.right: time.left
                            anchors.rightMargin: 6
                            text: row.modelData.app
                            elide: Text.ElideRight
                            color: Theme.fg
                            font.family: Theme.fontFamily
                            font.pixelSize: 11
                        }
                        Text {
                            id: time
                            anchors.right: parent.right
                            text: AppUsage.fmt(row.modelData.sec)
                            color: Qt.alpha(Theme.fg, 0.75)
                            font.family: Theme.fontFamilyAlt
                            font.pixelSize: 11
                        }
                        Rectangle {
                            anchors.bottom: parent.bottom
                            height: 2
                            radius: 1
                            color: Theme.accent
                            width: parent.width * row.modelData.sec / usage.topSec
                        }
                    }
                }
            }
        }
    }
}
