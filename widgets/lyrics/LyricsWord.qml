import QtQuick
import "../../services"

// One word of the lyrics, lying straight on the wallpaper. A dark outline and a hard shadow
// keep it readable over any picture. With `withFill` the word is lit from left to right as
// it is sung (`sung`, 0 .. 1).
Item {
    id: word

    property string text: ""
    property int pixelSize: 30
    property bool withFill: false
    property real sung: 0
    property color litColor: Theme.primary
    property color restColor: Qt.alpha(Theme.fg, 0.92)
    property color outlineColor: Theme.bg

    readonly property real stroke: Math.max(1, Math.round(word.pixelSize / 14))

    implicitWidth: label.implicitWidth + 2 * word.stroke + 2
    implicitHeight: label.implicitHeight + 2 * word.stroke + 2

    // the hard shadow, a little below the letters
    Text {
        x: label.x
        y: label.y + word.stroke
        text: word.text
        color: Qt.alpha(word.outlineColor, 0.7)
        font.family: Theme.fontFamilySans
        font.pixelSize: word.pixelSize
        font.weight: Font.DemiBold
    }

    // the outline: the letters again, one stroke out in each direction
    Repeater {
        model: [[-1, -1], [0, -1], [1, -1], [-1, 0], [1, 0], [-1, 1], [0, 1], [1, 1]]

        Text {
            required property var modelData
            x: label.x + modelData[0] * word.stroke
            y: label.y + modelData[1] * word.stroke
            text: word.text
            color: word.outlineColor
            font.family: Theme.fontFamilySans
            font.pixelSize: word.pixelSize
            font.weight: Font.DemiBold
        }
    }

    Text {
        id: label
        x: word.stroke + 1
        y: word.stroke + 1
        text: word.text
        color: word.restColor
        font.family: Theme.fontFamilySans
        font.pixelSize: word.pixelSize
        font.weight: Font.DemiBold
    }

    // the sung part: the same letters, shown only up to the point the word has reached
    Item {
        x: label.x
        y: label.y
        width: word.withFill ? label.implicitWidth * Math.max(0, Math.min(1, word.sung)) : 0
        height: label.implicitHeight
        clip: true

        Text {
            x: 0
            y: 0
            text: word.text
            color: word.litColor
            font.family: Theme.fontFamilySans
            font.pixelSize: word.pixelSize
            font.weight: Font.DemiBold
        }
    }
}
