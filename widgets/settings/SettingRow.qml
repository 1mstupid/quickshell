import QtQuick
import "../../services"

// One setting, from its entry in Settings.js (`def`): a switch for a bool, a slider with its
// value for a number, a field for a text. The value is read from UserSettings, or from
// WidgetLayout for a widget (which layout.json can override), so the row follows the file
// when it is edited by hand.
Item {
    id: row

    required property var def

    readonly property bool isBool: def.type === "bool"
    readonly property bool isText: def.type === "text"
    readonly property var value: def.layout ? WidgetLayout.shown(def.layout) : UserSettings[def.key]

    implicitHeight: isBool || isText ? 44 : 66

    // a number from the position on the track, held to the range and the step
    function at(x, w) {
        const f = Math.max(0, Math.min(1, x / w))
        const stepped = Math.round((def.min + f * (def.max - def.min)) / def.step) * def.step
        return Math.max(def.min, Math.min(def.max, stepped))
    }

    Text {
        x: 14
        y: row.isBool || row.isText ? (row.height - height) / 2 : 12
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

    // the text is written when the field is left or Enter is pressed, not at every key, and
    // Escape puts the old text back; a text that is not accepted (empty) does the same
    Rectangle {
        visible: row.isText
        anchors.right: parent.right
        anchors.rightMargin: 14
        anchors.verticalCenter: parent.verticalCenter
        width: Math.round(parent.width * 0.5)
        height: 28
        radius: 8
        color: Qt.alpha(Theme.fg, 0.08)
        border.width: field.activeFocus ? 1 : 0
        border.color: Theme.accent

        TextInput {
            id: field
            anchors.fill: parent
            anchors.leftMargin: 10
            anchors.rightMargin: 10
            verticalAlignment: TextInput.AlignVCenter
            clip: true
            selectByMouse: true
            text: row.isText ? row.value : ""
            color: Theme.fg
            selectionColor: Theme.accent
            selectedTextColor: Theme.bg
            font.family: Theme.fontFamilySans
            font.pixelSize: 12

            function revert() { text = Qt.binding(() => row.isText ? row.value : "") }
            onEditingFinished: {
                if (text.trim() !== row.value)
                    UserSettings.set(row.def.key, text)
                revert()
            }
            Keys.onEscapePressed: event => {
                revert()
                event.accepted = false
            }
        }
    }

    Text {
        visible: !row.isBool && !row.isText
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
        visible: !row.isBool && !row.isText
        x: 14
        y: 40
        width: parent.width - 28
        height: 10
        radius: 5
        color: Qt.alpha(Theme.fg, 0.10)
        clip: true

        Rectangle {
            width: row.isBool || row.isText ? 0 : parent.width * (row.value - row.def.min) / (row.def.max - row.def.min)
            height: parent.height
            radius: parent.radius
            color: Theme.accent
        }
    }

    // Dragging changes the running value, so the shell follows the hand; the file is written
    // once, when the button goes up.
    MouseArea {
        enabled: !row.isBool && !row.isText
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
