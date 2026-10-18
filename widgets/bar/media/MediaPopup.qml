import QtQuick
import "../../../components"


// Right-click popup for the Media pill. The body is MediaContent, the same
// component the dashboard's Media page uses.
Popout {
    id: root

    required property var media

    cardWidth: 320
    cardHeight: body.implicitHeight + 2 * cardPadding

    MediaContent {
        id: body
        anchors.left: parent.left
        anchors.right: parent.right
        media: root.media
    }
}
