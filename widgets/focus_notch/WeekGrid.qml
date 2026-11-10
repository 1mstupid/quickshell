import QtQuick
import "../../services"
import "../../services/menu"

// The Week tab: the schedule's grid. A row per day and a column per block, with
// the start of each block under its name, today's row and the block that is on
// now marked, and below it where the schedule comes from and what could not be
// read in it. The parent sets its place and size.
Item {
    id: weekTab

    readonly property var view: Schedule.week
    readonly property real dayW: 46
    readonly property real colW: view.cols.length > 0 ? (width - dayW) / view.cols.length : 0
    readonly property real rowH: view.rows.length > 0
        ? Math.min(26, (height - weekHead.height - weekFoot.height - 6) / view.rows.length) : 26
    readonly property var dayNames: ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]
    // the block that is on now, so its column can be marked
    readonly property string nowBlock: Schedule.current !== null ? Schedule.current.name : ""

    // block names and when each starts
    Row {
        id: weekHead

        Item {
            width: weekTab.dayW
            height: 32
        }
        Repeater {
            model: weekTab.view.cols

            Item {
                id: headCell
                required property var modelData
                width: weekTab.colW
                height: 32

                Column {
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 1

                    Text {
                        width: weekTab.colW - 6
                        text: headCell.modelData.name
                        color: headCell.modelData.name === weekTab.nowBlock ? Theme.accent : Qt.alpha(Theme.fg, 0.7)
                        font.family: Theme.fontFamily
                        font.pixelSize: 11
                        font.bold: true
                        elide: Text.ElideRight
                    }
                    Text {
                        text: headCell.modelData.time
                        color: Qt.alpha(Theme.fg, 0.4)
                        font.family: Theme.fontFamilyAlt
                        font.pixelSize: 10
                    }
                }
            }
        }
    }

    Column {
        y: weekHead.height + 2

        Repeater {
            model: weekTab.view.rows

            Item {
                id: weekRow
                required property var modelData
                readonly property bool today: modelData.day === Schedule.weekday

                width: weekTab.width
                height: weekTab.rowH

                Rectangle {
                    anchors.fill: parent
                    anchors.topMargin: 1
                    anchors.bottomMargin: 1
                    radius: 7
                    color: weekRow.today ? Qt.alpha(Theme.accent, 0.1) : "transparent"
                }
                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    x: 8
                    text: weekTab.dayNames[weekRow.modelData.day]
                    color: weekRow.today ? Theme.accent : Qt.alpha(Theme.fg, 0.7)
                    font.family: Theme.fontFamily
                    font.pixelSize: 11
                    font.bold: weekRow.today
                }
                Repeater {
                    model: weekRow.modelData.cells

                    Text {
                        id: weekCell
                        required property var modelData
                        required property int index
                        readonly property bool onNow: weekRow.today && weekTab.view.cols[index].name === weekTab.nowBlock

                        anchors.verticalCenter: parent.verticalCenter
                        x: weekTab.dayW + index * weekTab.colW
                        width: weekTab.colW - 6
                        text: modelData === "" ? "–" : modelData
                        color: onNow ? Theme.accent : modelData === "" ? Qt.alpha(Theme.fg, 0.25) : Theme.fg
                        font.family: Theme.fontFamily
                        font.pixelSize: 11
                        font.bold: onNow
                        elide: Text.ElideRight
                    }
                }
            }
        }
    }

    Text {
        visible: weekTab.view.rows.length === 0
        anchors.centerIn: parent
        text: "No Week table in schedule.md yet."
        color: Qt.alpha(Theme.fg, 0.5)
        font.family: Theme.fontFamily
        font.pixelSize: 12
    }

    // where the schedule comes from, and what could not be read in it
    Item {
        id: weekFoot
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        height: 28

        Text {
            anchors.verticalCenter: parent.verticalCenter
            anchors.left: parent.left
            anchors.leftMargin: 8
            anchors.right: createButton.visible ? createButton.left : parent.right
            anchors.rightMargin: 10
            text: Schedule.errors.length > 0
                ? "schedule.md · " + Schedule.errors[0] + (Schedule.errors.length > 1 ? "  (+" + (Schedule.errors.length - 1) + " more)" : "")
                : !Schedule.fromFile ? "Built-in template. Create schedule.md to make it yours."
                : "Edit schedule.md to change the clock or the week."
            color: Schedule.errors.length > 0 ? Theme.alert : Qt.alpha(Theme.fg, 0.5)
            font.family: Theme.fontFamily
            font.pixelSize: 11
            elide: Text.ElideRight
        }
        PillButton {
            id: createButton
            anchors.verticalCenter: parent.verticalCenter
            anchors.right: parent.right
            visible: !Schedule.fromFile
            label: "CREATE FILE"
            onClicked: Schedule.init()
        }
    }
}
