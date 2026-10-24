import QtQuick
import "../../services"
import "../../services/menu"

// Todo tab: an add row on top, then the items grouped by due date, overdue
// first. Click the circle to tick an item, the × to delete it.
Item {
    id: panel

    // the Loader in the menu sizes this panel
    anchors.fill: parent

    property int newPriority: 0
    readonly property var priorityLabels: ["–", "p1", "p2", "p3"]
    readonly property var rows: buildRows(Todo.items, Todo.today)

    // p1 before p2 before p3, unprioritised last
    function rank(task) {
        return task.priority === 0 ? 4 : task.priority
    }

    function buildRows(items, today) {
        const sorted = items.slice().sort((a, b) =>
            (Todo.groupOf(a.due) - Todo.groupOf(b.due))
            || (rank(a) - rank(b))
            || (a.due < b.due ? -1 : a.due > b.due ? 1 : 0))
        const out = []
        let group = -1
        for (const task of sorted) {
            const g = Todo.groupOf(task.due)
            if (g !== group) {
                out.push({ header: Todo.groupLabels[g] })
                group = g
            }
            out.push({ task: task })
        }
        return out
    }

    function addFromInput() {
        const due = dueField.text.trim()
        if (titleField.text.trim() === "" || !/^\d{4}-\d{2}-\d{2}$/.test(due))
            return
        Todo.add(titleField.text, due, newPriority)
        titleField.text = ""
        newPriority = 0
    }

    Column {
        anchors.fill: parent
        anchors.margins: 10
        spacing: 8

        Row {
            width: parent.width
            spacing: 6

            Rectangle {
                width: parent.width - dueBox.width - prioBtn.width - 12
                height: 26
                radius: 8
                color: Qt.alpha(Theme.fg, 0.07)

                TextInput {
                    id: titleField
                    anchors.verticalCenter: parent.verticalCenter
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.leftMargin: 8
                    anchors.rightMargin: 8
                    height: parent.height
                    clip: true
                    color: Theme.fg
                    font.family: Theme.fontFamily
                    font.pixelSize: 11
                    verticalAlignment: TextInput.AlignVCenter
                    Keys.onReturnPressed: panel.addFromInput()
                    Keys.onEnterPressed: panel.addFromInput()
                    Keys.onEscapePressed: MenuState.hide()
                }
                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    anchors.left: parent.left
                    anchors.leftMargin: 8
                    height: parent.height
                    visible: titleField.text === ""
                    text: "add a task"
                    color: Theme.disabled
                    font.family: Theme.fontFamily
                    font.pixelSize: 11
                    verticalAlignment: Text.AlignVCenter
                }
            }

            Rectangle {
                id: dueBox
                width: 92
                height: 26
                radius: 8
                color: Qt.alpha(Theme.fg, 0.07)

                TextInput {
                    id: dueField
                    anchors.verticalCenter: parent.verticalCenter
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.leftMargin: 8
                    anchors.rightMargin: 8
                    height: parent.height
                    clip: true
                    text: Todo.today
                    color: Theme.fg
                    font.family: Theme.fontFamily
                    font.pixelSize: 11
                    verticalAlignment: TextInput.AlignVCenter
                    Keys.onReturnPressed: panel.addFromInput()
                    Keys.onEnterPressed: panel.addFromInput()
                    Keys.onEscapePressed: MenuState.hide()
                }
            }

            Rectangle {
                id: prioBtn
                width: 34
                height: 26
                radius: 8
                color: Qt.alpha(Theme.fg, prioMouse.containsMouse ? 0.14 : 0.07)

                Text {
                    anchors.centerIn: parent
                    text: panel.priorityLabels[panel.newPriority]
                    color: panel.newPriority === 0 ? Theme.fg : Theme.accent
                    font.family: Theme.fontFamily
                    font.pixelSize: 12
                }
                MouseArea {
                    id: prioMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    onClicked: panel.newPriority = (panel.newPriority + 1) % 4
                }
            }
        }

        ListView {
            id: list
            width: parent.width
            height: parent.height - 26 - parent.spacing
            clip: true
            model: panel.rows
            boundsBehavior: Flickable.StopAtBounds

            delegate: Item {
                id: row
                required property var modelData
                readonly property bool isHeader: "header" in modelData
                readonly property var task: modelData.task

                width: list.width
                height: isHeader ? 22 : 24

                Text {
                    visible: row.isHeader
                    anchors.verticalCenter: parent.verticalCenter
                    text: row.modelData.header ?? ""
                    color: row.modelData.header === "Overdue" ? Theme.alert : Theme.accent
                    font.family: Theme.fontFamily
                    font.pixelSize: 11
                    font.bold: true
                }

                Row {
                    visible: !row.isHeader
                    anchors.verticalCenter: parent.verticalCenter
                    width: parent.width
                    height: 20
                    spacing: 8

                    Text {
                        id: tick
                        width: 14
                        height: parent.height
                        horizontalAlignment: Text.AlignHCenter
                        verticalAlignment: Text.AlignVCenter
                        text: row.task && row.task.done ? "●" : "○"
                        color: row.task && row.task.done ? Theme.accent : Theme.fg
                        font.family: Theme.fontFamily
                        font.pixelSize: 13
                        MouseArea {
                            anchors.fill: parent
                            onClicked: Todo.toggle(row.task)
                        }
                    }
                    Text {
                        width: parent.width - tick.width - dueText.width - prioText.width - delText.width - 4 * parent.spacing
                        text: row.task ? row.task.title : ""
                        height: parent.height
                        verticalAlignment: Text.AlignVCenter
                        elide: Text.ElideRight
                        color: row.task && row.task.done ? Qt.alpha(Theme.fg, 0.4) : Theme.fg
                        font.family: Theme.fontFamily
                        font.pixelSize: 12
                        font.strikeout: row.task ? row.task.done : false
                    }
                    Text {
                        id: dueText
                        height: parent.height
                        verticalAlignment: Text.AlignVCenter
                        text: row.task ? row.task.due.slice(5) : ""
                        color: row.task && row.task.due < Todo.today && !row.task.done
                            ? Theme.alert : Qt.alpha(Theme.fg, 0.5)
                        font.family: Theme.fontFamilyAlt
                        font.pixelSize: 11
                    }
                    Text {
                        id: prioText
                        height: parent.height
                        verticalAlignment: Text.AlignVCenter
                        text: row.task && row.task.priority ? "p" + row.task.priority : ""
                        color: Theme.accent
                        font.family: Theme.fontFamily
                        font.pixelSize: 11
                    }
                    Text {
                        id: delText
                        width: 14
                        height: parent.height
                        horizontalAlignment: Text.AlignHCenter
                        verticalAlignment: Text.AlignVCenter
                        text: "×"
                        color: delMouse.containsMouse ? Theme.alert : Qt.alpha(Theme.fg, 0.4)
                        font.family: Theme.fontFamily
                        font.pixelSize: 15
                        MouseArea {
                            id: delMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            onClicked: Todo.remove(row.task)
                        }
                    }
                }
            }
        }
    }
}
