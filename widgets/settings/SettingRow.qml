import QtQuick
import "../../services"

// One setting, from its entry in Settings.js (`def`): a switch for a bool, a slider with its
// value for a number. The value is read from UserSettings, or from WidgetLayout for a widget
// (which layout.json can override), so the row follows the file when it is edited by hand.
Item {
    id: row

    required property var def

    readonly property bool isBool: def.type === "bool"
    readonly property var value: def.layout ? WidgetLayout.shown(def.layout) : UserSettings[def.key]

    implicitHeight: isBool ? 44 : 66

    // a number from the position on the track, held to the range and the step
    function at(x, w) {
        const f = Math.max(0, Math.min(1, x / w))
        const stepped = Math.round((def.min + f * (def.max - def.min)) / def.step) * def.step
        return Math.max(def.min, Math.min(def.max, stepped))
    }

    Text {
        x: 14
        y: row.isBool ? (row.height - height) / 2 : 12
        text: row.def.label
        color: Theme.fg
        font.family: Theme.fontFamilySans
        font.pixelSize: 13
    }

    PillToggle {
        visible: row.isBool
        anchors.right: parent.right
        anchors.rightMargin: 14
        anchors.verticalCenter: parent.verticalCenter
        checked: row.value === true
        onToggled: {
            if (row.def.layout)
                WidgetLayout.toggle(row.def.layout)
            else
                UserSettings.set(row.def.key, !row.value)
        }
    }

    Text {
        visible: !row.isBool
        anchors.right: parent.right
        anchors.rightMargin: 14
        y: 12
        text: row.value + " " + (row.def.unit ?? "")
        color: Qt.alpha(Theme.fg, 0.6)
        font.family: Theme.fontFamilyNum
        font.pixelSize: 12
    }

    Rectangle {
        id: track
        visible: !row.isBool
        x: 14
        y: 40
        width: parent.width - 28
        height: 10
        radius: 5
        color: Qt.alpha(Theme.fg, 0.10)
        clip: true

        Rectangle {
            width: row.isBool ? 0 : parent.width * (row.value - row.def.min) / (row.def.max - row.def.min)
            height: parent.height
            radius: parent.radius
            color: Theme.accent
        }
    }

    // Dragging changes the running value, so the shell follows the hand; the file is written
    // once, when the button goes up.
    MouseArea {
        enabled: !row.isBool
        anchors.fill: track
        anchors.topMargin: -10
        anchors.bottomMargin: -10
        cursorShape: Qt.PointingHandCursor
        onPressed: mouse => UserSettings[row.def.key] = row.at(mouse.x, width)
        onPositionChanged: mouse => {
            if (pressed)
                UserSettings[row.def.key] = row.at(mouse.x, width)
        }
        onReleased: UserSettings.set(row.def.key, UserSettings[row.def.key])
    }
}
