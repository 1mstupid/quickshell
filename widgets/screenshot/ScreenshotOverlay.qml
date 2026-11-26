pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import Quickshell.Wayland
import "../../services"

// One frozen screen. The selection is shared (in Screenshot), and only the
// screen it is on is cut out of the dimming and gets the hint card.
PanelWindow {
    id: root

    required property var modelData
    required property var screenshot

    readonly property bool current: modelData.name === screenshot.activeName
    readonly property color scrim: Qt.alpha(Theme.bg, 0.6)

    screen: modelData
    visible: true
    anchors {
        top: true
        bottom: true
        left: true
        right: true
    }
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.layer: WlrLayer.Overlay
    // the frozen screen must not slide in over the live one
    WlrLayershell.namespace: "qs_screenshot"
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive
    color: "transparent"

    // Moves the selection onto this screen, so keys and capture act on it
    function claim() {
        if (root.current)
            return;
        root.screenshot.activeName = root.modelData.name;
        if (root.screenshot.mode === "screen")
            root.screenshot.setRegion(0, 0, root.width, root.height);
        else
            root.screenshot.resetSelection();
    }

    // Screen mode fills in the screen the selection is on, whichever overlay has focus
    Connections {
        target: root.screenshot

        function onModeChanged() {
            if (root.current && root.screenshot.mode === "screen")
                root.screenshot.setRegion(0, 0, root.width, root.height);
        }
    }

    Image {
        anchors.fill: parent
        source: "file://" + root.screenshot.tempPath(root.modelData.name)
        fillMode: Image.Stretch
        cache: false
    }

    // Dim everything; on the selection's screen, the four pieces around it
    readonly property bool cut: current && screenshot.hasSelection

    Rectangle {
        anchors.fill: parent
        color: root.scrim
        visible: !root.cut
    }
    Rectangle {
        visible: root.cut
        color: root.scrim
        x: 0
        y: 0
        width: root.width
        height: Math.max(0, root.screenshot.selY)
    }
    Rectangle {
        visible: root.cut
        color: root.scrim
        x: 0
        y: root.screenshot.selY + root.screenshot.selH
        width: root.width
        height: Math.max(0, root.height - y)
    }
    Rectangle {
        visible: root.cut
        color: root.scrim
        x: 0
        y: root.screenshot.selY
        width: Math.max(0, root.screenshot.selX)
        height: root.screenshot.selH
    }
    Rectangle {
        visible: root.cut
        color: root.scrim
        x: root.screenshot.selX + root.screenshot.selW
        y: root.screenshot.selY
        width: Math.max(0, root.width - x)
        height: root.screenshot.selH
    }
    Rectangle {
        visible: root.cut
        color: "transparent"
        border.width: 1
        border.color: Theme.accent
        x: root.screenshot.selX
        y: root.screenshot.selY
        width: root.screenshot.selW
        height: root.screenshot.selH
    }

    MouseArea {
        id: pointer

        property real startX: 0
        property real startY: 0
        property bool drawing: false

        anchors.fill: parent
        hoverEnabled: true
        cursorShape: root.screenshot.mode === "region" ? Qt.CrossCursor : Qt.ArrowCursor

        function clampX(v: real): real { return Math.max(0, Math.min(v, root.width)); }
        function clampY(v: real): real { return Math.max(0, Math.min(v, root.height)); }

        // Screen mode follows the pointer; a region is only moved to another screen by a press
        // there, so a drawn selection survives the pointer crossing monitors
        onEntered: {
            if (root.screenshot.mode === "screen")
                root.claim();
        }
        onPositionChanged: mouse => {
            if (root.screenshot.mode === "screen")
                root.claim();
            if (drawing)
                root.screenshot.setRegion(startX, startY, clampX(mouse.x), clampY(mouse.y));
        }
        onPressed: mouse => {
            if (root.screenshot.mode !== "region")
                return;
            root.claim();
            startX = clampX(mouse.x);
            startY = clampY(mouse.y);
            drawing = true;
            root.screenshot.setRegion(startX, startY, startX, startY);
        }
        onReleased: drawing = false
        onDoubleClicked: root.screenshot.finish("save")
    }

    Shortcut {
        sequence: "Escape"
        onActivated: root.screenshot.cancel()
    }

    Shortcut {
        sequences: ["Return", "Enter"]
        enabled: root.screenshot.hasSelection
        onActivated: root.screenshot.finish("save")
    }

    Shortcut {
        sequence: "c"
        enabled: root.screenshot.hasSelection
        onActivated: root.screenshot.finish("copy")
    }

    Shortcut {
        sequence: "e"
        enabled: root.screenshot.hasSelection
        onActivated: root.screenshot.finish("edit")
    }

    Shortcut {
        sequence: "r"
        onActivated: root.screenshot.setMode("region")
    }

    Shortcut {
        sequence: "s"
        onActivated: root.screenshot.setMode("screen")
    }

    // Hint card at the bottom centre, on the screen the selection is on
    Rectangle {
        visible: root.current
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: parent.bottom
        anchors.bottomMargin: Theme.edgeInset * 3
        width: hint.implicitWidth + Theme.edgeInset * 3
        height: hint.implicitHeight + Theme.edgeInset * 2
        radius: Theme.cardRadius
        color: Theme.altbg
        border.width: 1
        border.color: Theme.border

        Text {
            id: hint

            anchors.centerIn: parent
            color: Theme.fg
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSize
            text: root.screenshot.hasSelection
                ? Math.round(root.screenshot.selW) + " × " + Math.round(root.screenshot.selH) + "   ⏎ save · C copy · E edit · esc cancel"
                : (root.screenshot.mode === "screen" ? "S screen · R region · esc cancel" : "drag to select · S screen · esc cancel")
        }
    }
}
