import Quickshell
import Quickshell.Wayland
import QtQuick
import "../../services"
import "../notch"

// Usage dashboard: today, this week (Sunday to Saturday) or this month. It shows time
// per app, split by category. Today is charted by hour, the other spans by day,
// and today has a strip of sessions under the chart. It morphs out of
// the bar pill like the other panels, and `qs ipc call dashboard toggle` opens
// it. Escape or a click outside closes it.
PanelWindow {
    id: root

    screen: PillState.originScreen
    visible: false

    anchors {
        top: true
        left: true
        right: true
    }
    implicitHeight: PillState.pillTop + panelH + 12

    color: "transparent"
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: root.visible ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None
    WlrLayershell.namespace: "quickshell-dashboard"

    // ── Geometry ───────────────────────────────────────────────────────────
    // 12 pad, 46 header, 14 gap, body, 14 gap, 40 stats, 12 pad
    readonly property int panelW: 640
    readonly property int bodyH: 184
    // the body sits on two grey panels, each padded by panelPad on every side
    readonly property int panelPad: 10
    readonly property int panelH: bodyH + 2 * panelPad + 138
    readonly property int chartW: 380
    readonly property int chartPanelW: chartW + 2 * panelPad
    readonly property int listPanelW: panelW - 24 - chartPanelW - 16

    // the body's column, top to bottom: legend, gap, bars, labels, strip.
    // The legend wraps to as many rows as its categories need, and the bars
    // give up the same height, so more categories never push into other elements.
    readonly property int legendRowH: 24
    readonly property int legendH: legendRows.length > 0 ? legendRows.length * legendRowH - 10 : 0
    readonly property int barsTop: legendH + 8
    readonly property int chartH: Math.max(60, bodyH - barsTop - 16 - 24)
    readonly property int labelsTop: barsTop + chartH + 4
    readonly property int stripTop: labelsTop + 18

    // 0 = the bar pill, 1 = the full dashboard
    property real t: 0

    // the grey panels behind the chart and the list; the card itself stays dark
    readonly property color surface: Qt.rgba(0.17, 0.18, 0.2, 0.96)

    // ── Span ───────────────────────────────────────────────────────────────
    // "day" for today, "week" for this calendar week, "month" for this calendar month
    property string period: "day"
    readonly property var periodLabels: ({ day: "TODAY", week: "THIS WEEK", month: "THIS MONTH" })
    readonly property var periodTabs: [
        { key: "day", name: "Day" },
        { key: "week", name: "Week" },
        { key: "month", name: "Month" }
    ]

    // the day keys in the span, oldest first. Today is the day key for the day
    // span; the week runs Sunday to Saturday and the month runs from its first
    // day to its last, so future days in either span are empty.
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

    readonly property var listRows: allApps.slice(0, 6)
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

    // the apps behind one column: an hour of today, or a whole day (Apps mode)
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

    // one column's bar, split by category from the bottom up. Each piece gets
    // its distance from the bottom and its height.
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

    // ── Open / close ───────────────────────────────────────────────────────
    function openDash() {
        PillState.owner = "dashboard"
        visible = true
        morph.stop()
        morph.from = root.t
        morph.to = 1
        morph.start()
    }

    function closeDash() {
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
                if (PillState.owner === "dashboard")
                    PillState.owner = ""
            }
        }
    }

    Connections {
        target: DashboardState
        function onOpenChanged() {
            if (DashboardState.open)
                root.openDash()
            else
                root.closeDash()
        }
    }

    // another panel took the pill, so this one gives way
    Connections {
        target: PillState
        function onOwnerChanged() {
            if (PillState.owner !== "dashboard" && root.visible)
                DashboardState.hide()
        }
    }

    onVisibleChanged: {
        if (visible)
            keyHost.forceActiveFocus()
    }

    // a click in the band outside the card closes the dashboard. The window
    // is only as tall as the band, so clicks below it reach the windows underneath.
    MouseArea {
        anchors.fill: parent
        onClicked: DashboardState.hide()
    }

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

        // clicks on the notch stay on the notch, not the catcher behind it
        MouseArea { anchors.fill: parent }

        Item {
            id: keyHost
            anchors.fill: parent
            focus: true
            Keys.onEscapePressed: DashboardState.hide()
        }

        // content fades in during the second half of the morph
        Column {
            anchors.fill: parent
            anchors.margins: 12
            spacing: 14
            opacity: Math.max(0, (root.t - 0.5) * 2)

            // header: the span's label and total, then the Day | Week | Month tabs
            Item {
                width: parent.width
                height: 46

                Column {
                    spacing: 2

                    Text {
                        text: root.periodLabels[root.period]
                        color: Qt.alpha(Theme.fg, 0.75)
                        font.family: Theme.fontFamilyAlt
                        font.pixelSize: 10
                        font.letterSpacing: 1
                    }
                    Text {
                        text: AppUsage.fmt(root.totalSec)
                        color: Theme.fg
                        font.family: Theme.fontFamilyAlt
                        font.pixelSize: 22
                        font.bold: true
                    }
                }

                Row {
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 14

                    Repeater {
                        model: root.periodTabs

                        Text {
                            id: periodTab
                            required property var modelData
                            text: periodTab.modelData.name
                            color: root.period === periodTab.modelData.key ? Theme.accent : Qt.alpha(Theme.fg, 0.75)
                            font.family: Theme.fontFamily
                            font.pixelSize: 12
                            font.bold: root.period === periodTab.modelData.key
                            Behavior on color { ColorAnimation { duration: 120 } }

                            MouseArea {
                                anchors.fill: parent
                                anchors.margins: -6
                                cursorShape: Qt.PointingHandCursor
                                onClicked: root.period = periodTab.modelData.key
                            }
                        }
                    }
                }
            }

            // body: the chart column, then the most used apps
            Row {
                spacing: 16
                height: root.bodyH + 2 * root.panelPad

                // the chart's grey panel
                Item {
                    width: root.chartPanelW
                    height: root.bodyH + 2 * root.panelPad

                    Rectangle {
                        anchors.fill: parent
                        radius: 10
                        color: root.surface
                    }

                    Item {
                    x: root.panelPad
                    y: root.panelPad
                    width: root.chartW
                    height: root.bodyH

                    // legend, wrapped to fit the chart's width
                    Column {
                        id: legend
                        width: root.chartW
                        height: root.legendH
                        spacing: 10

                        Repeater {
                            model: root.legendRows

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
                                            color: root.colorFor(entry.modelData)
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
                        y: root.barsTop
                        width: parent.width
                        height: root.chartH

                        Repeater {
                            model: root.columns

                            Item {
                                id: col
                                required property int index
                                x: root.colX(col.index)
                                width: root.barW
                                height: bars.height

                                Repeater {
                                    model: root.segmentsFor(col.index)

                                    Rectangle {
                                        id: piece
                                        required property var modelData
                                        width: col.width
                                        y: col.height - piece.modelData.bottom - piece.modelData.size
                                        height: piece.modelData.size
                                        color: piece.modelData.color
                                    }
                                }

                                // the empty stage: an outline the height of the peak column.
                                // The segments fill it from the bottom, so a full column reaches the top.
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
                        model: root.columns

                        Text {
                            id: label
                            required property int index
                            x: label.index * root.slotW
                            y: root.labelsTop
                            width: root.slotW
                            horizontalAlignment: Text.AlignHCenter
                            text: root.labelFor(label.index)
                            color: Qt.alpha(Theme.fg, 0.85)
                            font.family: Theme.fontFamilyAlt
                            font.pixelSize: 9
                        }
                    }

                    // today's strip, for today only
                    Rectangle {
                        visible: root.period === "day"
                        y: root.stripTop
                        width: root.chartW
                        height: 6
                        radius: 3
                        color: Qt.alpha(Theme.fg, 0.06)

                        Repeater {
                            model: root.stripItems

                            Rectangle {
                                id: block
                                required property var modelData
                                x: (block.modelData.start - root.dayStartMs()) / 86400000 * root.chartW
                                width: Math.max(2, (block.modelData.end - block.modelData.start) / 86400000 * root.chartW)
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
                    width: root.listPanelW
                    height: root.bodyH + 2 * root.panelPad

                    Rectangle {
                        anchors.fill: parent
                        radius: 10
                        color: root.surface
                    }

                Column {
                    x: root.panelPad
                    y: root.panelPad
                    width: root.listPanelW - 2 * root.panelPad
                    spacing: 6

                    Text {
                        text: "MOST USED"
                        color: Qt.alpha(Theme.fg, 0.75)
                        font.family: Theme.fontFamilyAlt
                        font.pixelSize: 10
                        font.letterSpacing: 1
                    }

                    Repeater {
                        model: root.listRows

                        Item {
                            id: row
                            required property var modelData
                            width: parent.width
                            height: 22

                            Text {
                                anchors.left: parent.left
                                anchors.right: time.left
                                anchors.rightMargin: 8
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
                                width: parent.width * row.modelData.sec / root.topSec
                            }
                        }
                    }
                }
                }
            }

            // stats row
            Row {
                spacing: 28

                Repeater {
                    model: [
                        { label: "FIRST USE", value: root.firstUse },
                        { label: "NOTIFICATIONS", value: root.notifyText },
                        { label: "LONGEST SESSION", value: root.longestText },
                        { label: "POMODOROS", value: root.pomodoroText }
                    ]

                    Column {
                        id: stat
                        required property var modelData
                        spacing: 2

                        Text {
                            text: stat.modelData.label
                            color: Qt.alpha(Theme.fg, 0.75)
                            font.family: Theme.fontFamilyAlt
                            font.pixelSize: 9
                            font.letterSpacing: 1
                        }
                        Text {
                            text: stat.modelData.value
                            color: Theme.fg
                            font.family: Theme.fontFamilyAlt
                            font.pixelSize: 13
                            font.bold: true
                        }
                    }
                }
            }
        }
    }
}
