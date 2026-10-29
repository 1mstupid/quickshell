import Quickshell
import Quickshell.Wayland
import QtQuick
import "../../services"
import "../notch"

// Usage dashboard for today: focus time by hour, split by category, the most
// used apps, and a few stats. It morphs out of the bar pill like the other
// panels, and `qs ipc call dashboard toggle` opens it. Escape or a click
// outside closes it.
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
    // 12 pad, 46 header, 14 gap, 160 body, 14 gap, 40 stats, 12 pad
    readonly property int panelW: 640
    readonly property int panelH: 298
    readonly property int bodyH: 160
    readonly property int chartW: 380
    readonly property int chartH: 130
    readonly property real slotW: chartW / 24

    // 0 = the bar pill, 1 = the full dashboard
    property real t: 0

    // ── Data ───────────────────────────────────────────────────────────────
    // each binding names the day and reads revision, so it refreshes every
    // tick and rolls over at midnight
    readonly property var allApps: AppUsage.totals(AppUsage.dayKey(), AppUsage.revision)
    readonly property var topApps: allApps.slice(0, 6)
    readonly property var hours: AppUsage.hoursOf(AppUsage.dayKey(), AppUsage.revision)
    readonly property var sessions: AppUsage.sessionsOf(AppUsage.dayKey(), AppUsage.revision)
    readonly property var categoryOrder: AppUsage.categoryTotals(AppUsage.dayKey(), AppUsage.revision)
        .map(r => r.category)
    readonly property real totalSec: allApps.reduce((s, r) => s + r.sec, 0)
    readonly property real topSec: topApps.length > 0 ? topApps[0].sec : 1

    readonly property string firstUse: sessions.length > 0
        ? Qt.formatTime(new Date(sessions[0].start), "HH:mm") : "—"
    readonly property real longestSec: sessions.reduce((m, s) => Math.max(m, (s.end - s.start) / 1000), 0)
    readonly property string longestText: longestSec > 0
        ? Math.max(1, Math.round(longestSec / 60)) + " min" : "—"
    readonly property string notifyText: String(AppUsage.notificationsOf(AppUsage.dayKey(), AppUsage.revision))

    // the tallest hour sets the scale, so a quiet day still fills the chart
    function hourTotal(h) {
        const a = hours[h] ?? {}
        return Object.keys(a).reduce((s, k) => s + a[k], 0)
    }
    readonly property real peakSec: Math.max(60, ...Array.from({ length: 24 }, (_, h) => hourTotal(h)))

    function colorFor(c) {
        if (c === "Other")
            return Qt.alpha(Theme.fg, 0.25)
        return Qt.alpha(Theme.accent, Math.max(0.35, 1 - Math.max(0, categoryOrder.indexOf(c)) * 0.2))
    }

    // one hour's bar, split by category from the bottom up. Each piece gets its
    // distance from the bottom and its height, in pixels.
    function segmentsFor(h) {
        const a = hours[h] ?? {}
        const sums = {}
        for (const app of Object.keys(a)) {
            const c = AppUsage.categoryOf(app)
            sums[c] = (sums[c] ?? 0) + a[app]
        }
        const scale = chartH / peakSec
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

            // header: the label and today's total
            Column {
                spacing: 2

                Text {
                    text: "TODAY"
                    color: Qt.alpha(Theme.fg, 0.5)
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

            // body: the hourly chart with its legend, then the most used apps
            Row {
                spacing: 16
                height: root.bodyH

                Item {
                    width: root.chartW
                    height: root.bodyH

                    Item {
                        id: bars
                        width: parent.width
                        height: root.chartH

                        Repeater {
                            model: 24

                            Item {
                                id: col
                                required property int index
                                x: col.index * root.slotW
                                width: root.slotW - 4
                                height: bars.height

                                Repeater {
                                    model: root.segmentsFor(col.index)

                                    Rectangle {
                                        required property var modelData
                                        width: col.width
                                        y: col.height - modelData.bottom - modelData.size
                                        height: modelData.size
                                        color: modelData.color
                                    }
                                }
                            }
                        }
                    }

                    // hour labels, every six hours
                    Repeater {
                        model: [0, 6, 12, 18]

                        Text {
                            required property int modelData
                            x: modelData * root.slotW
                            y: bars.height + 4
                            text: String(modelData).padStart(2, "0")
                            color: Qt.alpha(Theme.fg, 0.4)
                            font.family: Theme.fontFamilyAlt
                            font.pixelSize: 9
                        }
                    }

                    // legend: one entry per category, in the same order as the bars
                    Row {
                        y: bars.height + 22
                        spacing: 12

                        Repeater {
                            model: root.categoryOrder

                            Row {
                                required property var modelData
                                spacing: 6

                                Rectangle {
                                    anchors.verticalCenter: parent.verticalCenter
                                    width: 8
                                    height: 8
                                    radius: 4
                                    color: root.colorFor(modelData)
                                }
                                Text {
                                    text: modelData
                                    color: Qt.alpha(Theme.fg, 0.6)
                                    font.family: Theme.fontFamilyAlt
                                    font.pixelSize: 10
                                }
                            }
                        }
                    }
                }

                Column {
                    width: root.panelW - 24 - root.chartW - 16
                    spacing: 6

                    Text {
                        text: "MOST USED"
                        color: Qt.alpha(Theme.fg, 0.5)
                        font.family: Theme.fontFamilyAlt
                        font.pixelSize: 10
                        font.letterSpacing: 1
                    }

                    Repeater {
                        model: root.topApps

                        Item {
                            required property var modelData
                            width: parent.width
                            height: 22

                            Text {
                                anchors.left: parent.left
                                anchors.right: time.left
                                anchors.rightMargin: 8
                                text: modelData.app
                                elide: Text.ElideRight
                                color: Theme.fg
                                font.family: Theme.fontFamily
                                font.pixelSize: 11
                            }
                            Text {
                                id: time
                                anchors.right: parent.right
                                text: AppUsage.fmt(modelData.sec)
                                color: Qt.alpha(Theme.fg, 0.5)
                                font.family: Theme.fontFamilyAlt
                                font.pixelSize: 11
                            }
                            Rectangle {
                                anchors.bottom: parent.bottom
                                height: 2
                                radius: 1
                                color: Theme.accent
                                width: parent.width * modelData.sec / root.topSec
                            }
                        }
                    }
                }
            }

            // stats row
            Row {
                spacing: 36

                Repeater {
                    model: [
                        { label: "FIRST USE", value: root.firstUse },
                        { label: "NOTIFICATIONS", value: root.notifyText },
                        { label: "LONGEST SESSION", value: root.longestText }
                    ]

                    Column {
                        required property var modelData
                        spacing: 2

                        Text {
                            text: modelData.label
                            color: Qt.alpha(Theme.fg, 0.5)
                            font.family: Theme.fontFamilyAlt
                            font.pixelSize: 9
                            font.letterSpacing: 1
                        }
                        Text {
                            text: modelData.value
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
