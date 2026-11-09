import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import "../../services"
import "../../services/menu"

// Tasks on the wallpaper layer, top-left: today's date, then what is overdue,
// due today and due tomorrow, from todo.md. Click a circle to tick a task, the
// × on a hovered row deletes it. Tasks are added by editing the file. Hidden
// while the overview is open. Only the card takes pointer events.
PanelWindow {
    id: root

    screen: PillState.originScreen
    anchors {
        left: WidgetLayout.hasLeft("todo")
        right: WidgetLayout.hasRight("todo")
        top: WidgetLayout.hasTop("todo")
        bottom: WidgetLayout.hasBottom("todo")
    }
    margins {
        left: WidgetLayout.insetX("todo")
        right: WidgetLayout.insetX("todo")
        top: WidgetLayout.insetY("todo")
        bottom: WidgetLayout.insetY("todo")
    }
    implicitWidth: 240
    implicitHeight: card.height

    exclusionMode: ExclusionMode.Ignore
    color: "transparent"
    WlrLayershell.layer: WlrLayer.Background
    WlrLayershell.namespace: "quickshell-todo"
    mask: Region { item: card }

    Component.onCompleted: WidgetLayout.register("todo", root)

    visible: WidgetLayout.shown("todo") && !Overview.open

    IpcHandler {
        target: "todo"
        function toggle(): void { WidgetLayout.toggle("todo") }
    }

    // task rows shown at most; what does not fit is counted in a "+N more" line
    readonly property int maxRows: 8
    readonly property var rows: buildRows(Todo.items, Todo.today)
    readonly property date day: Todo.toDate(Todo.today)

    // p1 before p2 before p3, unprioritised last
    function rank(task) {
        return task.priority === 0 ? 4 : task.priority
    }

    function buildRows(items, today) {
        const tomorrow = Todo.addDays(today, 1)
        const order = (a, b) => (a.done - b.done) || (rank(a) - rank(b)) || (a.line - b.line)
        const overdue = items.filter(t => !t.done && t.due < today)
            .sort((a, b) => (a.due < b.due ? -1 : a.due > b.due ? 1 : 0) || order(a, b))
        const now = items.filter(t => t.due === today).sort(order)
        const next = items.filter(t => !t.done && t.due === tomorrow).sort(order)

        const open = now.filter(t => !t.done).length
        const head = open > 0
            ? "You have <b>" + open + "</b> " + (open === 1 ? "task" : "tasks") + " today"
            : now.length > 0 ? "All done for today" : "Nothing due today"

        const out = []
        let room = root.maxRows
        let hidden = 0
        // a section shows only if some of its tasks fit; today's always shows
        const section = (text, kind, tasks, always) => {
            const shown = tasks.slice(0, room)
            room -= shown.length
            hidden += tasks.length - shown.length
            if (shown.length === 0 && !always)
                return
            out.push({ header: text, kind: kind })
            for (const t of shown)
                out.push({ task: t })
        }
        section("Overdue", "alert", overdue, false)
        section(head, "today", now, true)
        section("Tomorrow", "dim", next, false)
        if (hidden > 0)
            out.push({ more: hidden })
        return out
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

        Column {
            id: col
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.margins: card.pad
            spacing: 2

            // the bar shows only the time, so the date lives here
            Row {
                spacing: 6
                bottomPadding: 6

                Text {
                    text: Qt.formatDate(root.day, "dddd")
                    color: Theme.fg
                    font.family: Theme.fontFamily
                    font.pixelSize: 13
                    font.bold: true
                }
                Text {
                    text: Qt.formatDate(root.day, "MMMM d")
                    color: Qt.alpha(Theme.fg, 0.6)
                    font.family: Theme.fontFamily
                    font.pixelSize: 13
                }
            }

            Repeater {
                model: root.rows

                Item {
                    id: row
                    required property var modelData
                    readonly property bool isHeader: "header" in modelData
                    readonly property bool isMore: "more" in modelData
                    readonly property var task: modelData.task ?? null
                    // done tasks are never listed as overdue, so a past day means overdue
                    readonly property bool isLate: task !== null && task.due < Todo.today

                    width: col.width
                    height: isHeader ? 24 : isMore ? 18 : 22

                    Text {
                        visible: row.isHeader
                        anchors.left: parent.left
                        anchors.bottom: parent.bottom
                        anchors.bottomMargin: 2
                        width: parent.width
                        elide: Text.ElideRight
                        textFormat: Text.StyledText
                        text: row.isHeader ? row.modelData.header : ""
                        color: row.isHeader && row.modelData.kind === "alert" ? Theme.alert
                             : row.isHeader && row.modelData.kind === "dim" ? Qt.alpha(Theme.fg, 0.4)
                             : Qt.alpha(Theme.fg, 0.6)
                        font.family: Theme.fontFamily
                        font.pixelSize: 11
                    }

                    Text {
                        visible: row.isMore
                        anchors.verticalCenter: parent.verticalCenter
                        text: row.isMore ? "+" + row.modelData.more + " more" : ""
                        color: Qt.alpha(Theme.fg, 0.4)
                        font.family: Theme.fontFamily
                        font.pixelSize: 11
                    }

                    // a task row; the hover shows the × without moving anything
                    Item {
                        id: taskRow
                        visible: row.task !== null
                        anchors.fill: parent

                        HoverHandler { id: hover }

                        // the circle and the title tick the task
                        MouseArea {
                            anchors.fill: parent
                            anchors.rightMargin: 30
                            cursorShape: Qt.PointingHandCursor
                            onClicked: Todo.toggle(row.task)
                        }

                        Rectangle {
                            id: tick
                            anchors.left: parent.left
                            anchors.verticalCenter: parent.verticalCenter
                            width: 14
                            height: 14
                            radius: 7
                            color: row.task && row.task.done ? Theme.accent : "transparent"
                            border.width: 1.5
                            border.color: row.task && row.task.done ? Theme.accent : Qt.alpha(Theme.fg, 0.4)
                            Behavior on color { ColorAnimation { duration: 120 } }
                        }

                        Text {
                            anchors.left: tick.right
                            anchors.leftMargin: 8
                            anchors.right: meta.left
                            anchors.rightMargin: 8
                            anchors.verticalCenter: parent.verticalCenter
                            // titles are typed by hand, so never read them as markup
                            textFormat: Text.PlainText
                            text: row.task ? row.task.title : ""
                            elide: Text.ElideRight
                            color: row.task && row.task.done ? Qt.alpha(Theme.fg, 0.4) : Theme.fg
                            font.family: Theme.fontFamily
                            font.pixelSize: 12
                            font.strikeout: row.task ? row.task.done : false
                        }

                        // the day for overdue tasks, then the hour, then the priority
                        Row {
                            id: meta
                            anchors.right: del.left
                            anchors.rightMargin: 4
                            anchors.verticalCenter: parent.verticalCenter
                            spacing: 6

                            Text {
                                visible: row.isLate
                                text: row.task ? row.task.due.slice(5) : ""
                                color: Theme.alert
                                font.family: Theme.fontFamilyAlt
                                font.pixelSize: 11
                            }
                            Text {
                                visible: row.task !== null && row.task.time !== ""
                                text: row.task ? row.task.time : ""
                                color: Qt.alpha(Theme.fg, 0.5)
                                font.family: Theme.fontFamilyAlt
                                font.pixelSize: 11
                            }
                            Text {
                                visible: row.task !== null && row.task.priority > 0
                                text: row.task ? "p" + row.task.priority : ""
                                color: Theme.accent
                                font.family: Theme.fontFamily
                                font.pixelSize: 11
                            }
                        }

                        Text {
                            id: del
                            anchors.right: parent.right
                            anchors.verticalCenter: parent.verticalCenter
                            width: 14
                            horizontalAlignment: Text.AlignHCenter
                            text: "×"
                            opacity: hover.hovered ? 1 : 0
                            color: Qt.alpha(Theme.fg, 0.5)
                            font.family: Theme.fontFamily
                            font.pixelSize: 15
                            Behavior on opacity { NumberAnimation { duration: 120 } }

                            // no hoverEnabled here: a hovering child would take the hover
                            // from the row's handler and hide the × under the pointer
                            MouseArea {
                                anchors.fill: parent
                                anchors.margins: -4
                                cursorShape: Qt.PointingHandCursor
                                onClicked: Todo.remove(row.task)
                            }
                        }
                    }
                }
            }
        }
    }
}
