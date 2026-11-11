import QtQuick

Item {
    id: root

    property string text: ""
    property real progress: 0.0 // Ranges from 0.0 (unfilled) to 1.0 (fully sung)
    property color restingColor: Qt.alpha("#ffffff", 0.35)
    property color activeColor: "#ffffff"
    property int fontSize: 24
    property font customFont: Qt.font({ family: "Sans Serif", pixelSize: fontSize })

    implicitWidth: baseText.implicitWidth
    implicitHeight: baseText.implicitHeight

    // 1. Resting (Unfilled) Text underneath
    Text {
        id: baseText
        anchors.verticalCenter: parent.verticalCenter
        anchors.left: parent.left
        text: root.text
        color: root.restingColor
        font: root.customFont
    }

    // 2. Active (Filled) Text clipped progressively from left to right
    Item {
        id: fillMask
        anchors.verticalCenter: parent.verticalCenter
        anchors.left: parent.left
        width: baseText.width * Math.max(0.0, Math.min(1.0, root.progress))
        height: baseText.height
        clip: true

        Text {
            id: activeText
            x: 0
            y: (fillMask.height - height) / 2
            text: root.text
            color: root.activeColor
            font: root.customFont
            width: baseText.width // Lock width so text doesn't reflow/squish during clipping
        }
    }
}
