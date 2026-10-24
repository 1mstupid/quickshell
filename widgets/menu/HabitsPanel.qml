import QtQuick
import "../../services"
import "../../services/menu"

// Habits tab: one row per habit with a check-in circle, the name, a five-week
// garden (one column per week, Sunday at the top) and the current streak.
// Habits are listed in habits.json; adding or removing them is done in that file.
Item {
    id: panel

    // the Loader in the menu sizes this panel
    anchors.fill: parent

    // 35 day strings, oldest first; days after today stay empty in the garden
    readonly property var dates: Habits.gridDates()

    Text {
        anchors.centerIn: parent
        visible: Habits.data.habits.length === 0
        horizontalAlignment: Text.AlignHCenter
        text: "No habits yet.\nAdd them to ~/.local/xdg/config/habits.json"
        color: Theme.disabled
        font.family: Theme.fontFamily
        font.pixelSize: 11
    }

    ListView {
        anchors.fill: parent
        anchors.margins: 10
        clip: true
        spacing: 4
        boundsBehavior: Flickable.StopAtBounds
        model: Habits.data.habits

        delegate: Item {
            id: row
            required property var modelData
            width: ListView.view.width
            height: 28

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
                id: nameText
                anchors.left: tickBox.right
                anchors.leftMargin: 8
                anchors.right: garden.left
                anchors.rightMargin: 8
                anchors.verticalCenter: parent.verticalCenter
                text: row.modelData.name
                elide: Text.ElideRight
                color: row.doneToday ? Qt.alpha(Theme.fg, 0.5) : Theme.fg
                font.family: Theme.fontFamily
                font.pixelSize: 12
            }

            // garden: columns are weeks, rows are weekdays from Sunday
            Grid {
                id: garden
                anchors.right: streakText.left
                anchors.rightMargin: 8
                anchors.verticalCenter: parent.verticalCenter
                rows: 7
                columns: 5
                flow: Grid.TopToBottom
                spacing: 1

                Repeater {
                    model: panel.dates

                    Rectangle {
                        id: cell
                        required property string modelData
                        readonly property bool future: modelData > Habits.data.day
                        readonly property bool completed: Habits.doneOn(row.modelData.id, modelData)

                        width: 3
                        height: 3
                        radius: 1
                        color: future ? "transparent"
                             : completed ? Theme.accent
                             : Qt.alpha(Theme.fg, 0.1)
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
