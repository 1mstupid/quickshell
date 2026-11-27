import QtQuick
import Quickshell
import Quickshell.Wayland
import "../../services"
import "../../services/menu"
import "../../services/menu/StudyMath.js" as StudyMath

// Today's study on the wallpaper: the total, and a row per hour in six 10-minute
// cells, filled where the task timer ran, one colour per subject. Hovering a block
// names its task and the length of that run. The timer itself is worked from the
// focus strip. Hidden while the overview is open.
PanelWindow {
    id: root

    screen: PillState.originScreen
    anchors {
        left: WidgetLayout.hasLeft("study")
        right: WidgetLayout.hasRight("study")
        top: WidgetLayout.hasTop("study")
        bottom: WidgetLayout.hasBottom("study")
    }
    margins {
        left: WidgetLayout.insetX("study")
        right: WidgetLayout.insetX("study")
        top: WidgetLayout.insetY("study")
        bottom: WidgetLayout.insetY("study")
    }
    implicitWidth: 240
    implicitHeight: card.height

    exclusionMode: ExclusionMode.Ignore
    color: "transparent"
    WlrLayershell.layer: WlrLayer.Background
    WlrLayershell.namespace: "quickshell-study"
    // only the card takes pointer events, so the rest of the wallpaper stays clickable
    mask: Region { item: card }

    Component.onCompleted: WidgetLayout.register("study", root)

    visible: WidgetLayout.shown("study") && !Overview.open

    // passing AppUsage.revision makes these re-evaluate each tick and at midnight
    readonly property string today: {
        AppUsage.revision
        return AppUsage.dayKey()
    }
    readonly property double now: {
        AppUsage.revision
        return Math.max(Date.now(), TaskFocus.now)
    }
    // the saved runs, and the one on the clock now
    readonly property var runs: {
        const out = AppUsage.studyOf(today, AppUsage.revision)
        if (TaskFocus.running)
            out.push({ title: TaskFocus.title, start: TaskFocus.startMs, end: now })
        return out
    }
    readonly property var day: StudyMath.grid(runs, now)
    readonly property int rows: day.last - day.first + 1

    // every subject the schedule can ask for, so colours hold from day to day
    readonly property var scheduled: {
        const out = []
        for (const row of Schedule.week.rows)
            for (const c of row.cells)
                if (c !== "")
                    out.push(c)
        return out
    }
    readonly property var order: StudyMath.subjectOrder(scheduled, runs)
    // today's subjects, in the order first studied: the legend
    readonly property var studied: {
        const out = []
        for (const s of day.segments) {
            const name = StudyMath.subjectOf(s.title)
            if (out.indexOf(name) < 0)
                out.push(name)
        }
        return out
    }

    // the hovered segment's place in the grid, or -1 for the row when none
    property int hoverHour: -1
    property real hoverAt: 0
    // looked up on each change, so the length of a running block keeps counting
    readonly property var hovered: hoverHour < 0 ? null
        : StudyMath.segmentAt(day.segments, hoverHour, hoverAt)

    // the accent's saturation and lightness, held where hues can still be told apart
    function colorOf(title) {
        const i = Math.max(0, order.indexOf(StudyMath.subjectOf(title)))
        return Qt.hsla(StudyMath.hueAt(Theme.accent.hslHue, i),
            Math.max(0.5, Theme.accent.hslSaturation),
            Math.min(0.7, Math.max(0.5, Theme.accent.hslLightness)), 1)
    }

    Rectangle {
        id: card

        readonly property int pad: 14

        width: root.width
        height: col.implicitHeight + 2 * pad
        radius: Theme.cardRadius
        // translucent under the Liquid glass setting, so a compositor blur shows through the card
        color: Qt.alpha(Theme.bg, UserSettings.liquidGlass ? 0.72 : 0.92)

        Column {
            id: col
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.margins: card.pad
            spacing: 10

            // the date and the day's total, or the hovered task and its run
            Item {
                width: col.width
                height: total.implicitHeight

                Text {
                    anchors.left: parent.left
                    anchors.right: total.left
                    anchors.rightMargin: 10
                    anchors.baseline: total.baseline
                    text: root.hovered !== null ? root.hovered.title
                        : Qt.formatDate(new Date(root.now), "ddd, d MMM")
                    color: root.hovered !== null ? Theme.fg : Qt.alpha(Theme.fg, 0.6)
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontSize
                    elide: Text.ElideRight
                }
                Text {
                    id: total
                    anchors.right: parent.right
                    text: AppUsage.fmt((root.hovered !== null ? root.hovered.ms : root.day.totalMs) / 1000)
                    color: Theme.fg
                    font.family: Theme.fontFamilyDisplay
                    font.pixelSize: 22
                    font.bold: true
                }
            }

            Item {
                id: chart

                readonly property int labelW: 25
                readonly property int rowH: 15
                // a whole number of pixels per cell, so the lines stay sharp
                readonly property int cellW: Math.floor((width - labelW - 1) / 6)
                readonly property int gridW: cellW * 6

                width: col.width
                height: root.rows * rowH + 1

                Repeater {
                    model: root.rows

                    Text {
                        required property int index
                        y: index * chart.rowH
                        height: chart.rowH
                        verticalAlignment: Text.AlignVCenter
                        text: String(root.day.first + index).padStart(2, "0")
                        color: Qt.alpha(Theme.fg, 0.45)
                        font.family: Theme.fontFamilyAlt
                        font.pixelSize: 10
                    }
                }

                // the filled stretches. The model is a count, so a tick moves the
                // blocks in place instead of building them again.
                Repeater {
                    model: root.day.segments.length

                    Rectangle {
                        required property int index
                        readonly property var seg: root.day.segments[index] ?? null

                        visible: seg !== null
                        x: seg ? chart.labelW + seg.from * chart.gridW : 0
                        y: seg ? (seg.hour - root.day.first) * chart.rowH : 0
                        // a run of seconds still shows as a sliver
                        width: seg ? Math.max(2, (seg.to - seg.from) * chart.gridW) : 0
                        height: chart.rowH
                        color: seg ? root.colorOf(seg.title) : "transparent"
                    }
                }

                // the grid lines, drawn over the blocks
                Repeater {
                    model: root.rows + 1

                    Rectangle {
                        required property int index
                        x: chart.labelW
                        y: index * chart.rowH
                        width: chart.gridW + 1
                        height: 1
                        color: Theme.border
                    }
                }
                Repeater {
                    model: 7

                    Rectangle {
                        required property int index
                        x: chart.labelW + index * chart.cellW
                        width: 1
                        height: chart.height
                        color: Theme.border
                    }
                }

                MouseArea {
                    anchors.fill: parent
                    hoverEnabled: true
                    onPositionChanged: m => {
                        root.hoverAt = (m.x - chart.labelW) / chart.gridW
                        root.hoverHour = root.day.first + Math.floor(m.y / chart.rowH)
                    }
                    onExited: root.hoverHour = -1
                }
            }

            // today's subjects and their colours
            Flow {
                visible: root.studied.length > 0
                width: col.width
                spacing: 10

                Repeater {
                    model: root.studied

                    Row {
                        id: entry
                        required property string modelData
                        spacing: 5

                        Rectangle {
                            anchors.verticalCenter: parent.verticalCenter
                            width: 8
                            height: 8
                            radius: 4
                            color: root.colorOf(entry.modelData)
                        }
                        Text {
                            width: Math.min(implicitWidth, col.width - 13)
                            text: entry.modelData
                            color: Qt.alpha(Theme.fg, 0.85)
                            font.family: Theme.fontFamily
                            font.pixelSize: 11
                            elide: Text.ElideRight
                        }
                    }
                }
            }
        }
    }
}
