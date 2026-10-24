import QtQuick
import QtQuick.Effects
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import "../../services"
import "../../services/WallpaperPalette.js" as Palette
import "../notch"


PanelWindow {
    id: root

    // sits on the origin screen, at the top edge, under the bar pill
    screen: PillState.originScreen
    visible: false

    anchors {
        top: true
        left: true
        right: true
    }
    implicitHeight: PillState.pillTop + bandHeight + 12

    exclusionMode: ExclusionMode.Ignore
    color: "transparent"

    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: root.visible ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None
    WlrLayershell.namespace: "quickshell-wallpapers"

    // the band the pill grows into, and the size of the centre card inside it
    property int bandWidth: 900
    property int bandHeight: 220
    property int cardWidth: 360
    property int cardHeight: 200

    // carousel spacing: gap between neighbouring cards, and how fast they shrink
    property real gap: 24
    property real minScale: 0.55
    property real scaleStep: 0.15

    // 0 = the bar pill, 1 = the full band
    property real t: 0

    property var wallpapers: []
    property int currentIndex: 0
    property string applyingPath: ""
    property bool randomPending: false

    // scale of a card `u` slots away from the centre
    function scaleAt(u) {
        return Math.max(minScale, 1 - scaleStep * Math.abs(u))
    }

    // centre-to-centre distance from the card `k` slots out to the one `k+1` slots out
    function pitch(k) {
        return cardWidth * (scaleAt(k) + scaleAt(k + 1)) / 2 + gap
    }

    // horizontal offset of a card `u` slots from the centre; fractional u interpolates
    function offsetFor(u) {
        const a = Math.abs(u)
        const whole = Math.floor(a)
        let total = 0
        for (let j = 0; j < whole; j++)
            total += pitch(j)
        return Math.sign(u) * (total + (a - whole) * pitch(whole))
    }

    onVisibleChanged: {
        if (visible) {
            lister.running = true
            keyHost.forceActiveFocus()
        }
    }

    // another panel took the pill, so this one gives way
    Connections {
        target: PillState
        function onOwnerChanged() {
            if (PillState.owner !== "wallpapers" && root.visible)
                root.close()
        }
    }

    function openPicker() {
        PillState.owner = "wallpapers"
        visible = true
        morph.stop()
        morph.from = root.t
        morph.to = 1
        morph.start()
    }

    function close() {
        morph.stop()
        morph.from = root.t
        morph.to = 0
        morph.start()
    }

    function toggle() {
        if (visible && PillState.owner === "wallpapers")
            close()
        else
            openPicker()
    }

    function apply(path) {
        applyingPath = path
        if (!visible)
            openPicker()
        canvas.loadImage("file://" + path)
    }

    function applyRandom() {
        randomPending = true
        lister.running = true
    }

    // Quickshell IPC Handler
    IpcHandler {
        target: "wallpapers"
        function toggle(): void { root.toggle() }
        function random(): void { root.applyRandom() }
        function set(path: string): void { root.apply(path) }
    }

    // grows the card from the pill (t=0) into the band (t=1); on the way back
    // it hides the window and releases the pill
    NumberAnimation {
        id: morph
        target: root
        property: "t"
        duration: 480
        easing.type: Easing.InOutCubic
        onFinished: {
            if (root.t < 0.5) {
                root.visible = false
                if (PillState.owner === "wallpapers")
                    PillState.owner = ""
            }
        }
    }

    property var _found: []
    Process {
        id: lister
        command: ["sh", "-c",
            "find -L \"" + Theme.configDir + "/../.local/share/wallpapers\" -maxdepth 1 -type f " +
            "\\( -iname '*.png' -o -iname '*.jpg' -o -iname '*.jpeg' \\) | sort"]
        stdout: SplitParser {
            onRead: line => { if (line.trim() !== "") root._found.push(line.trim()) }
        }
        onRunningChanged: {
            if (running) {
                root._found = []
            } else {
                root.wallpapers = root._found
                if (root.randomPending) {
                    root.randomPending = false
                    if (root.wallpapers.length > 0)
                        root.apply(root.wallpapers[
                            Math.floor(Math.random() * root.wallpapers.length)])
                }
            }
        }
    }

    // Keyboard & Vim navigation; Esc closes
    Item {
        id: keyHost
        anchors.fill: parent
        focus: true

        Keys.onPressed: event => {
            if (event.key === Qt.Key_Escape) {
                root.close()
                event.accepted = true
            } else if (event.key === Qt.Key_Left || event.text === "h") {
                if (root.currentIndex > 0)
                    root.currentIndex--
                event.accepted = true
            } else if (event.key === Qt.Key_Right || event.text === "l") {
                if (root.currentIndex < root.wallpapers.length - 1)
                    root.currentIndex++
                event.accepted = true
            } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                if (root.currentIndex >= 0 && root.wallpapers.length > 0)
                    root.apply(root.wallpapers[root.currentIndex])
                event.accepted = true
            }
        }
    }

    // the card: starts exactly over the bar pill, then widens into the band
    // the outline is a notch, drawn behind the card and sized to it
    Notch {
        id: outline
        bodyWidth: card.width
        bodyHeight: card.height
        x: card.x - bodyX
        y: card.y
    }

    // the card gives the carousel its geometry; the notch above is what's drawn
    Rectangle {
        id: card

        readonly property real fromW: PillState.pillWidth
        readonly property real fromH: PillState.pillHeight

        width: fromW + (root.bandWidth - fromW) * root.t
        height: fromH + (root.bandHeight - fromH) * root.t
        x: (root.width - width) / 2
        y: PillState.pillTop
        color: "transparent"
    }

    // only the band takes clicks; everything around it passes through
    mask: Region { item: outline }

    Canvas {
        id: canvas
        x: 0
        y: 0
        width: 100
        height: 50
        visible: false

        onImageLoaded: {
            const url = "file://" + root.applyingPath
            if (root.applyingPath !== "" && isImageError(url))
                root.applyingPath = ""
            else
                requestPaint()
        }

        onPaint: {
            if (root.applyingPath === "")
                return
            const url = "file://" + root.applyingPath
            if (!isImageLoaded(url))
                return
            const ctx = getContext("2d")
            ctx.clearRect(0, 0, width, height)
            ctx.drawImage(url, 0, 0, width, height)
            const data = ctx.getImageData(0, 0, width, height).data
            unloadImage(url)
            root.finish(data)
        }
    }

    // carousel: cards are placed from their scaled widths, so neighbours
    // take only the space they show. Fades in during the second half of the morph.
    Item {
        id: carousel
        x: card.x + 8
        y: card.y + 8
        width: card.width - 16
        height: card.height - 16
        clip: true
        opacity: Math.max(0, (root.t - 0.5) * 2)

        // animated centre position, so moving between cards glides
        property real pos: root.currentIndex
        Behavior on pos {
            NumberAnimation { duration: 180; easing.type: Easing.OutCubic }
        }

        Repeater {
            model: root.wallpapers

            Item {
                id: cell
                required property int index
                required property string modelData

                // slots from the centre; fractional while the carousel is moving
                readonly property real d: cell.index - carousel.pos
                readonly property bool busy: root.applyingPath === modelData

                width: root.cardWidth
                height: root.cardHeight
                x: carousel.width / 2 - width / 2 + root.offsetFor(d)
                y: (carousel.height - height) / 2
                scale: root.scaleAt(d)
                opacity: Math.abs(d) > 3 ? 0 : Math.max(0.4, 1 - 0.2 * Math.abs(d))

                Rectangle {
                    anchors.fill: parent
                    radius: 12
                    color: Qt.alpha(Theme.fg, 0.06)

                    // hidden rounded shape, used only to mask the thumbnail
                    Item {
                        id: thumbMask
                        anchors.fill: parent
                        anchors.margins: 2
                        visible: false
                        layer.enabled: true

                        Rectangle {
                            anchors.fill: parent
                            radius: 10
                            color: "white"
                        }
                    }

                    Image {
                        anchors.fill: parent
                        anchors.margins: 2
                        source: "file://" + cell.modelData
                        sourceSize.width: root.cardWidth * 2
                        fillMode: Image.PreserveAspectCrop
                        asynchronous: true
                        layer.enabled: true
                        layer.effect: MultiEffect {
                            maskEnabled: true
                            maskSource: thumbMask
                        }
                    }

                    Rectangle {
                        anchors.fill: parent
                        radius: 12
                        color: "transparent"
                        border.width: cell.busy ? 3 : (mouse.containsMouse || root.currentIndex === cell.index) ? 2 : 0
                        border.color: cell.busy ? Theme.accent : Qt.alpha(Theme.accent, 0.8)

                        SequentialAnimation on opacity {
                            running: cell.busy
                            loops: Animation.Infinite
                            alwaysRunToEnd: true
                            NumberAnimation { to: 0.4; duration: 120 }
                            NumberAnimation { to: 1.0; duration: 120 }
                        }
                    }

                    MouseArea {
                        id: mouse
                        anchors.fill: parent
                        hoverEnabled: true
                        onClicked: {
                            root.currentIndex = cell.index
                            root.apply(cell.modelData)
                        }
                    }
                }
            }
        }
    }

    // Palette math lives in services/WallpaperPalette.js. This widget samples
    // the image, applies the result, and closes the picker.
    function finish(d) {
        const result = Palette.derive(d)
        if (!result)
            return
        Quickshell.execDetached(
            ["wallpaper-theme", root.applyingPath]
                .concat(result.palette).concat(result.ansi))
        root.applyingPath = ""
        root.close()
    }
}
