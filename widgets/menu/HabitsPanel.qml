import QtQuick
import "../../services"
import "../../services/menu"

// Habits tab: a header of faded weekday abbreviations, then one row per habit
// with a check-in circle, the name, one cell per day of the current week
// (Monday first) and the current streak. Habits are listed in habits.json;
// adding or removing them is done in that file.
Item {
    id: panel

    // the Loader in the menu sizes this panel
    anchors.fill: parent

    readonly property var dayLabels: ["Mo", "Tu", "We", "Th", "Fr", "Sa", "Su"]
    readonly property int cellSize: 20
    readonly property int cellGap: 4
    // room for the streak and the gap before it, shared by header and rows
    readonly property int streakSpace: 36

    // the seven date strings of this week, Monday first; empty until the file loads
    readonly property var week: {
        const today = Habits.data.day
        if (today === "")
            return []
        const offset = (Habits.toDate(today).getDay() + 6) % 7
        const out = []
        for (let i = 0; i < 7; i++)
            out.push(Habits.addDays(today, i - offset))
        return out
    }

    Text {
        anchors.centerIn: parent
        visible: Habits.data.habits.length === 0
        horizontalAlignment: Text.AlignHCenter
        text: "No habits yet.\nAdd them to ~/.local/xdg/config/habits.json"
        color: Theme.disabled
        font.family: Theme.fontFamily
        font.pixelSize: 11
    }

    // weekday header, aligned with the cells in each row below
    Row {
        id: header
        anchors.top: parent.top
        anchors.right: parent.right
        anchors.topMargin: 10
        anchors.rightMargin: 10 + panel.streakSpace
        spacing: panel.cellGap

        Repeater {
            model: panel.dayLabels

            Text {
                required property string modelData
                width: panel.cellSize
                horizontalAlignment: Text.AlignHCenter
                text: modelData
                color: Qt.alpha(Theme.fg, 0.35)
                font.family: Theme.fontFamilyAlt
                font.pixelSize: 9
                font.bold: true
            }
        }
    }

    ListView {
        anchors.top: header.bottom
        anchors.topMargin: 4
        anchors.bottom: parent.bottom
        anchors.bottomMargin: 10
        anchors.left: parent.left
        anchors.leftMargin: 10
        anchors.right: parent.right
        anchors.rightMargin: 10
        clip: true
        spacing: 4
        boundsBehavior: Flickable.StopAtBounds
        model: Habits.data.habits

        delegate: Item {
            id: row
            required property var modelData
            width: ListView.view.width
            height: panel.cellSize

            readonly property bool doneToday: modelData.status === "completed"

            // check-in circle; click to tick the habit for today
            Rectangle {
                id: tickBox
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
                width: 16
                height: 16
                radius: 8
                color: row.doneToday ? Theme.accent : "transparent"
                border.width: 1.5
                border.color: row.doneToday ? Theme.accent : Qt.alpha(Theme.fg, 0.4)

                MouseArea {
                    anchors.fill: parent
                    anchors.margins: -4
                    cursorShape: Qt.PointingHandCursor
                    onClicked: Habits.toggle(row.modelData.id)
                }
            }

            Text {
                anchors.left: tickBox.right
                anchors.leftMargin: 8
                anchors.right: cells.left
                anchors.rightMargin: 8
                anchors.verticalCenter: parent.verticalCenter
                text: row.modelData.name
                elide: Text.ElideRight
                color: row.doneToday ? Qt.alpha(Theme.fg, 0.5) : Theme.fg
                font.family: Theme.fontFamily
                font.pixelSize: 12
            }

            // one cell per day of this week; the streak sits at the right edge
            Row {
                id: cells
                anchors.right: streakText.left
                anchors.rightMargin: 8
                anchors.verticalCenter: parent.verticalCenter
                spacing: panel.cellGap

                Repeater {
                    model: panel.week

                    Rectangle {
                        id: cell
                        required property string modelData
                        readonly property bool future: modelData > Habits.data.day
                        readonly property bool today: modelData === Habits.data.day
                        readonly property bool completed: Habits.doneOn(row.modelData.id, modelData)

                        width: panel.cellSize
                        height: panel.cellSize
                        radius: 5
                        color: completed ? Theme.accent
                             : future ? Qt.alpha(Theme.fg, 0.04)
                             : Qt.alpha(Theme.fg, 0.1)
                        border.width: today && !completed ? 1 : 0
                        border.color: Qt.alpha(Theme.fg, 0.35)
                    }
                }
            }

            Text {
                id: streakText
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                width: 28
                horizontalAlignment: Text.AlignRight
                readonly property int run: Habits.streak(row.modelData.id)
                text: run > 0 ? run + "d" : ""
                color: Theme.accent
                font.family: Theme.fontFamilyAlt
                font.pixelSize: 11
                font.bold: true
            }
        }
    }
}
