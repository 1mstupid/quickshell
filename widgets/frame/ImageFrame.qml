import QtQuick
import QtQuick.Effects
import Quickshell
import Quickshell.Wayland
import "../../services"

// A picture on the wallpaper, in a fixed shape, cropped from its centre. There can
// be several: each is added and removed in the layout edit mode, which also sets its
// shape and size. It starts empty and takes an image file dropped on it; a file that
// cannot be read leaves it empty. Hidden while the overview is open.
PanelWindow {
    id: root

    // the layout id, frame-N, from the Variants in shell.qml
    required property string modelData

    screen: PillState.originScreen
    anchors {
        left: WidgetLayout.hasLeft(root.modelData)
        right: WidgetLayout.hasRight(root.modelData)
        top: WidgetLayout.hasTop(root.modelData)
        bottom: WidgetLayout.hasBottom(root.modelData)
    }
    margins {
        left: WidgetLayout.insetX(root.modelData)
        right: WidgetLayout.insetX(root.modelData)
        top: WidgetLayout.insetY(root.modelData)
        bottom: WidgetLayout.insetY(root.modelData)
    }
    // width and height at scale 1
    readonly property var base: WidgetLayout.shapes[WidgetLayout.shapeOf(root.modelData)]
    readonly property real zoom: WidgetLayout.scaleOf(root.modelData)
    implicitWidth: Math.round(base[0] * zoom)
    implicitHeight: Math.round(base[1] * zoom)

    exclusionMode: ExclusionMode.Ignore
    color: "transparent"
    WlrLayershell.layer: WlrLayer.Background
    WlrLayershell.namespace: "quickshell-frame"

    Component.onCompleted: WidgetLayout.register(root.modelData, root)

    visible: WidgetLayout.shown(root.modelData) && !Overview.open

    readonly property string path: WidgetLayout.imageOf(root.modelData)
    readonly property bool filled: picture.status === Image.Ready

    // the empty frame, also behind a picture that is still loading
    Rectangle {
        id: card

        anchors.fill: parent
        radius: Theme.cardRadius
        // translucent under the Liquid glass setting, so a compositor blur shows through the card
        color: Qt.alpha(Theme.bg, UserSettings.liquidGlass ? 0.72 : 0.92)
        border.width: 1
        border.color: Theme.border
        visible: !root.filled

        Column {
            anchors.centerIn: parent
            spacing: 8
            visible: picture.status !== Image.Loading

            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: "󰋩"
                color: Qt.alpha(Theme.fg, 0.45)
                font.family: Theme.fontFamily
                font.pixelSize: 28
            }
            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: "drop an image"
                color: Qt.alpha(Theme.fg, 0.45)
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSize
            }
        }
    }

    Image {
        id: picture
        anchors.fill: parent
        source: root.path !== "" ? ShareService.fileUrl(root.path) : ""
        fillMode: Image.PreserveAspectCrop
        asynchronous: true
        // phone photos are often stored sideways, with the turn noted in the file
        autoTransform: true
        // decoded once for the largest scale, so resizing does not reload it
        sourceSize.width: root.base[0] * WidgetLayout.maxScale
        sourceSize.height: root.base[1] * WidgetLayout.maxScale
        mipmap: true
        visible: root.filled

        layer.enabled: true
        layer.effect: MultiEffect {
            maskEnabled: true
            maskSource: corners
            // keeps the rounded edge smooth
            maskThresholdMin: 0.5
            maskSpreadAtMin: 1.0
        }
    }

    Item {
        id: corners
        anchors.fill: parent
        visible: false
        layer.enabled: true

        Rectangle {
            anchors.fill: parent
            radius: Theme.cardRadius
            color: "white"
        }
    }

    // lit while a file is held over the frame
    Rectangle {
        anchors.fill: parent
        radius: Theme.cardRadius
        color: "transparent"
        border.width: 2
        border.color: Theme.accent
        visible: drop.containsDrag
    }

    // the first image among the dropped files fills the frame; anything else is
    // refused, so it cannot clear a picture
    DropArea {
        id: drop
        anchors.fill: parent
        keys: ["text/uri-list"]
        onDropped: event => {
            const image = ShareService.pathsOf(event.urls)
                .find(p => /\.(png|jpe?g|webp|gif|bmp)$/i.test(p))
            if (image === undefined) {
                event.accepted = false
                return
            }
            WidgetLayout.save(root.modelData, { image: image })
            event.accept(Qt.CopyAction)
        }
    }
}
