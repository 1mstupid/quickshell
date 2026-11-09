import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import "../../services"
import "../../services/menu"
import "../../services/menu/MonthGrid.js" as Month

// Habits on the wallpaper layer, top-right: one habit per page, shown as this
// month's calendar with its streak and total. Click today's cell to tick the
// habit. The dots under the calendar are the pages, filled for the habits done
// today; click a dot or scroll to change page. Habits are listed in
// habits.json. Hidden while the overview is open. Only the card takes pointer events.
PanelWindow {
    id: root

    screen: PillState.originScreen
    anchors {
        left: WidgetLayout.hasLeft("habits")
        right: WidgetLayout.hasRight("habits")
        top: WidgetLayout.hasTop("habits")
        bottom: WidgetLayout.hasBottom("habits")
    }
    margins {
        left: WidgetLayout.insetX("habits")
        right: WidgetLayout.insetX("habits")
        top: WidgetLayout.insetY("habits")
        bottom: WidgetLayout.insetY("habits")
    }
    implicitWidth: 240
    implicitHeight: card.height

    exclusionMode: ExclusionMode.Ignore
    color: "transparent"
    WlrLayershell.layer: WlrLayer.Background
    WlrLayershell.namespace: "quickshell-habits"
    mask: Region { item: card }

    Component.onCompleted: WidgetLayout.register("habits", root)

    // the day is empty only until habits.json has been read
    visible: WidgetLayout.shown("habits") && !Overview.open && Habits.data.day !== ""

    IpcHandler {
        target: "habits"
        function toggle(): void { WidgetLayout.toggle("habits") }
    }

    readonly property var habits: Habits.data.habits
    readonly property int count: habits.length
    readonly property string day: Habits.data.day

    // the page asked for, kept in range if habits are removed from the file
    property int page: 0
    readonly property int current: count > 0 ? Math.min(page, count - 1) : 0
    readonly property var habit: count > 0 ? habits[current] : null
    readonly property var cells: Month.grid(day)

    readonly property int cellSize: 26
    readonly property int cellGap: 5
    readonly property var dayLabels: ["M", "T", "W", "T", "F", "S", "S"]

    function step(delta) {
        if (count > 1)
            page = (current + delta + count) % count
    }

    Rectangle {
        id: card

        readonly property int pad: 14

        width: root.width
        height: col.implicitHeight + 2 * pad
        radius: 12
        color: Qt.alpha(Theme.bg, 0.92)
        border.width: 1
        border.color: Qt.alpha(Theme.border, 0.6)

        // a wheel notch changes the page; the sum keeps a touchpad from skipping several
        WheelHandler {
            property real sum: 0
            onWheel: event => {
                sum += event.angleDelta.y
                if (Math.abs(sum) < 120)
                    return
                root.step(sum < 0 ? 1 : -1)
                sum = 0
            }
        }

        Column {
            id: col
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.margins: card.pad
            spacing: 10

            Text {
                visible: root.count === 0
                width: col.width
                wrapMode: Text.WordWrap
                text: "No habits yet.\nAdd them to ~/.local/xdg/config/habits.json"
                color: Theme.disabled
                font.family: Theme.fontFamily
                font.pixelSize: 11
            }

            // habit name, and the month the calendar shows
            Item {
                visible: root.count > 0
                width: col.width
                height: 18

                Text {
                    anchors.left: parent.left
                    anchors.right: month.left
                    anchors.rightMargin: 8
                    anchors.verticalCenter: parent.verticalCenter
                    textFormat: Text.PlainText
                    text: root.habit ? root.habit.name : ""
                    elide: Text.ElideRight
                    color: Theme.fg
                    font.family: Theme.fontFamily
                    font.pixelSize: 13
                    font.bold: true
                }
                Text {
                    id: month
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    text: Qt.formatDate(Habits.toDate(root.day), "MMM yyyy")
                    color: Qt.alpha(Theme.fg, 0.5)
                    font.family: Theme.fontFamilyAlt
                    font.pixelSize: 11
                }
            }

            Row {
                visible: root.count > 0
                spacing: 28

                Repeater {
                    model: [
                        { label: "STREAK", value: root.habit ? Habits.streak(root.habit.id) + " d" : "" },
                        { label: "TOTAL", value: root.habit ? String(Habits.total(root.habit.id)) : "" }
                    ]

                    Column {
                        id: stat
                        required property var modelData
                        spacing: 2

                        Text {
                            text: stat.modelData.label
                            color: Qt.alpha(Theme.fg, 0.5)
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

            // the weekday header and the month's days, Monday first
            Column {
                visible: root.count > 0
                spacing: 6

                Row {
                    spacing: root.cellGap

                    Repeater {
                        model: root.dayLabels

                        Text {
                            required property string modelData
                            width: root.cellSize
                            horizontalAlignment: Text.AlignHCenter
                            text: modelData
                            color: Qt.alpha(Theme.fg, 0.35)
                            font.family: Theme.fontFamilyAlt
                            font.pixelSize: 9
                            font.bold: true
                        }
                    }
                }

                Grid {
                    columns: 7
                    spacing: root.cellGap

                    Repeater {
                        model: root.cells

                        Rectangle {
                            id: cell
                            required property var modelData
                            readonly property bool today: modelData.date === root.day
                            readonly property bool future: modelData.date > root.day
                            readonly property bool done: root.habit !== null
                                && Habits.doneOn(root.habit.id, modelData.date)

                            width: root.cellSize
                            height: root.cellSize
                            radius: root.cellSize / 2
                            // days of the neighbouring months are shown faded
                            opacity: modelData.inMonth ? 1 : 0.35
                            color: done ? Theme.accent
                                 : today || future ? "transparent"
                                 : Qt.alpha(Theme.fg, 0.08)
                            border.width: today && !done ? 1 : 0
                            border.color: Qt.alpha(Theme.fg, 0.5)
                            Behavior on color { ColorAnimation { duration: 120 } }

                            Text {
                                anchors.centerIn: parent
                                text: Number(cell.modelData.date.slice(8))
                                color: cell.done ? Theme.bg
                                     : cell.today ? Theme.fg
                                     : Qt.alpha(Theme.fg, cell.future ? 0.25 : 0.6)
                                font.family: Theme.fontFamilyAlt
                                font.pixelSize: 11
                                font.bold: cell.done
                            }

                            // only today can be ticked; past days are read-only, as in Habits
                            MouseArea {
                                anchors.fill: parent
                                enabled: cell.today
                                cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
                                onClicked: Habits.toggle(root.habit.id)
                            }
                        }
                    }
                }
            }

            // the pages: the current one is long, the filled ones are done today
            Row {
                visible: root.count > 1
                anchors.horizontalCenter: parent.horizontalCenter
                spacing: 6

                Repeater {
                    model: root.habits

                    Rectangle {
                        id: dot
                        required property var modelData
                        required property int index
                        readonly property bool selected: index === root.current
                        readonly property bool done: Habits.doneOn(modelData.id, root.day)

                        width: selected ? 16 : 6
                        height: 6
                        radius: 3
                        color: done ? Theme.accent : Qt.alpha(Theme.fg, selected ? 0.4 : 0.15)
                        Behavior on width {
                            NumberAnimation { duration: 200; easing.type: Easing.OutCubic }
                        }
                        Behavior on color { ColorAnimation { duration: 150 } }

                        MouseArea {
                            anchors.fill: parent
                            anchors.margins: -4
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root.page = dot.index
                        }
                    }
                }
            }
        }
    }
}
