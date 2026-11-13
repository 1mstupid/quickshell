import QtQuick
import QtQuick.Effects
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import "../../services"
import "../../services/WallpaperPalette.js" as Palette
import "../notch"
import "Colorschemes.js" as Schemes

// The colorscheme picker: the wallpaper picker's carousel and band, with a few fixed
// schemes and "Wallpaper", whose colours are derived from the wallpaper in use, as the
// wallpaper picker does. Left and Right (or h and l) move, Enter applies, Escape closes.
// Every scheme goes through the same wallpaper-theme script, so the files it writes
// stay in step; a fixed scheme just hands it its own colours. The scheme in use is
// remembered in ~/.local/xdg/config/colorscheme-current, and the picker opens on it.
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
    WlrLayershell.namespace: "quickshell-colorschemes"

    // wide enough for the five cards; a narrower screen clips the outer ones
    property int bandWidth: Math.min(1040, (root.screen ? root.screen.width : 1920) - 48)
    property int bandHeight: 230
    property int pad: 14
    property int headerH: 22
    property int carouselH: 140
    property int cardWidth: 220
    property int cardHeight: 140
    property int nameH: 18

    readonly property string dirPath: Quickshell.env("HOME") + "/.local/share/wallpapers"

    // carousel spacing: gap between neighbouring cards, and how fast they shrink
    property real gap: 24
    property real minScale: 0.55
    property real scaleStep: 0.15

    // 0 = the bar pill, 1 = the full band
    property real t: 0

    readonly property var schemes: Schemes.SCHEMES
    property int currentIndex: 0

    // the scheme in use, and the wallpaper the script is given. Both are read from the
    // files the pickers write, at start, so the first opening is not the one that loads them.
    property string currentId: ""
    property string wallpaperPath: ""
    readonly property string stateFile: Quickshell.env("HOME") + "/.local/xdg/config/colorscheme-current"
    readonly property string wallpaperFile: Quickshell.env("HOME") + "/.local/xdg/config/wallpaper-current"
    // set while the wallpaper is being sampled
    property bool deriving: false

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

    // on the scheme in use; "wallpaper" when none was remembered, as that is what a
    // wallpaper change leaves behind
    function focusCurrent() {
        const i = Schemes.indexOfId(currentId === "" ? "wallpaper" : currentId)
        currentIndex = i >= 0 ? i : 0
    }

    // wallpaper-theme takes the wallpaper path first; without one nothing can be applied
    FileView {
        path: root.wallpaperFile
        watchChanges: true
        onFileChanged: reload()
        onLoaded: root.wallpaperPath = text().trim()
    }

    // the wallpaper picker writes this file too, so a new wallpaper (whose colours are
    // derived) shows up here as the scheme in use
    FileView {
        path: root.stateFile
        watchChanges: true
        onFileChanged: reload()
        onLoaded: {
            root.currentId = text().trim()
            if (!root.visible)
                root.focusCurrent()
        }
    }

    onVisibleChanged: {
        if (visible)
            keyHost.forceActiveFocus()
    }

    // another panel took the pill, so this one gives way
    Connections {
        target: PillState
        function onOwnerChanged() {
            if (PillState.owner !== "colorschemes" && root.visible)
                root.close()
        }
    }

    function openPicker() {
        focusCurrent()
        PillState.owner = "colorschemes"
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
        if (visible && PillState.owner === "colorschemes")
            close()
        else
            openPicker()
    }

    // qs ipc call colorschemes toggle
    IpcHandler {
        target: "colorschemes"
        function toggle(): void { root.toggle() }
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
                if (PillState.owner === "colorschemes")
                    PillState.owner = ""
            }
        }
    }

    // Process to find a random wallpaper inside the scheme's subfolder
    Process {
        id: randomWallpaperPicker
        property var scheme: null
        stdout: SplitParser {
            onRead: line => {
                const imgPath = line.trim()
                const finalImg = imgPath !== "" ? imgPath : root.wallpaperPath
                if (randomWallpaperPicker.scheme) {
                    root.runWithWallpaper(randomWallpaperPicker.scheme.id, randomWallpaperPicker.scheme.palette, randomWallpaperPicker.scheme.ansi, finalImg)
                    randomWallpaperPicker.scheme = null
                }
            }
        }
    }

    function apply(scheme) {
        if (root.deriving || root.wallpaperPath === "")
            return
        if (scheme.id === "wallpaper") {
            root.deriving = true
            canvas.loadImage("file://" + root.wallpaperPath)
        } else {
            randomWallpaperPicker.scheme = scheme
            randomWallpaperPicker.command = [
                "sh", "-c",
                "dir=\"" + root.dirPath + "/" + scheme.id + "\"; " +
                "img=\"\"; " +
                "if [ -d \"$dir\" ]; then " +
                "  img=$(find -L \"$dir\" -type f \\( -iname '*.png' -o -iname '*.jpg' -o -iname '*.jpeg' \\) 2>/dev/null | shuf -n 1); " +
                "fi; " +
                "echo \"$img\""
            ]
            randomWallpaperPicker.running = true
        }
    }

    function runWithWallpaper(id, palette, ansi, imgPath) {
        Quickshell.execDetached(
            ["wallpaper-theme", imgPath].concat(palette).concat(ansi))

        root.currentId = id
        Quickshell.execDetached(["sh", "-c", "printf '%s\\n' \"$1\" >| \"$2\"",
                                   "sh", id, root.stateFile])
        
        // Update current wallpaper file so everything stays in sync
        Quickshell.execDetached(["sh", "-c", "printf '%s\\n' \"$1\" >| \"$2\"",
                                   "sh", imgPath, root.wallpaperFile])
        root.close()
    }

    // Keyboard & Vim navigation; Esc closes
    Item {
        id: keyHost
        anchors.fill: parent
        focus: true

        Keys.onPressed: event => {
            const enter = event.key === Qt.Key_Return || event.key === Qt.Key_Enter
            if (event.key === Qt.Key_Escape) {
                root.close()
                event.accepted = true
            } else if (event.key === Qt.Key_Left || event.text === "h") {
                if (root.currentIndex > 0)
                    root.currentIndex--
                event.accepted = true
            } else if (event.key === Qt.Key_Right || event.text === "l") {
                if (root.currentIndex < root.schemes.length - 1)
                    root.currentIndex++
                event.accepted = true
            } else if (enter) {
                root.apply(root.schemes[root.currentIndex])
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

    // the card gives the layout its geometry; the notch above is what's drawn
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

    // header: what this is. Fades in during the second half of the morph.
    Text {
        x: card.x + root.pad
        y: card.y + root.pad
        width: Math.max(0, card.width - 2 * root.pad)
        height: root.headerH
        verticalAlignment: Text.AlignVCenter
        elide: Text.ElideRight
        text: "Colorscheme"
        color: Qt.alpha(Theme.fg, 0.5)
        font.family: Theme.fontFamilyAlt
        font.pixelSize: 11
        opacity: Math.max(0, (root.t - 0.5) * 2)
    }

    // carousel: cards are placed from their scaled widths, so neighbours
    // take only the space they show. Fades in during the second half of the morph.
    Item {
        id: carousel
        x: card.x + root.pad
        y: card.y + root.pad + root.headerH + 12
        width: Math.max(0, card.width - 2 * root.pad)
        height: root.carouselH
        clip: true
        opacity: Math.max(0, (root.t - 0.5) * 2)

        // animated centre position, so moving between cards glides
        property real pos: root.currentIndex
        Behavior on pos {
            NumberAnimation { duration: 180; easing.type: Easing.OutCubic }
        }

        Repeater {
            model: root.schemes

            Item {
                id: cell
                required property int index
                required property var modelData

                // slots from the centre; fractional while the carousel is moving
                readonly property real d: cell.index - carousel.pos
                readonly property bool current: root.currentIndex === cell.index
                readonly property bool isWallpaper: modelData.id === "wallpaper"
                readonly property bool busy: isWallpaper && root.deriving
                // the card's own colours: a fixed scheme shows itself, the wallpaper card the
                // theme in use
                readonly property color bgCol: isWallpaper ? Theme.bg : modelData.palette[0]
                readonly property color fgCol: isWallpaper ? Theme.fg : modelData.palette[2]
                readonly property color accentCol: isWallpaper ? Theme.accent : modelData.palette[4]

                width: root.cardWidth
                height: root.cardHeight
                x: carousel.width / 2 - width / 2 + root.offsetFor(d)
                y: (carousel.height - height) / 2
                scale: root.scaleAt(d)
                opacity: Math.abs(d) > 3 ? 0 : Math.max(0.35, 1 - 0.25 * Math.abs(d))
                // a card that cannot be seen is not drawn
                visible: opacity > 0

                Rectangle {
                    anchors.fill: parent
                    radius: 10
                    color: cell.bgCol

                    // hidden rounded shape, used only to mask the wallpaper
                    Item {
                        id: thumbMask
                        anchors.fill: parent
                        visible: false
                        layer.enabled: true

                        Rectangle {
                            anchors.fill: parent
                            radius: 10
                            color: "white"
                        }
                    }

                    // the wallpaper card shows the wallpaper it will take its colours from
                    Image {
                        anchors.fill: parent
                        visible: cell.isWallpaper
                        source: cell.isWallpaper && root.wallpaperPath !== "" ? "file://" + root.wallpaperPath : ""
                        sourceSize.width: root.cardWidth * 2
                        fillMode: Image.PreserveAspectCrop
                        asynchronous: true
                        opacity: status === Image.Ready ? 1 : 0
                        Behavior on opacity { NumberAnimation { duration: 160 } }
                        layer.enabled: true
                        layer.effect: MultiEffect {
                            maskEnabled: true
                            maskSource: thumbMask
                        }
                    }

                    // a fixed scheme: its text and accent on its background, and its six colours
                    Item {
                        anchors.fill: parent
                        visible: !cell.isWallpaper

                        Text {
                            x: 16
                            y: 12
                            text: "Aa"
                            color: cell.fgCol
                            font.family: Theme.fontFamilySans
                            font.pixelSize: 28
                            font.weight: Font.DemiBold
                        }
                        Rectangle {
                            x: 16
                            y: 54
                            width: 28
                            height: 3
                            radius: 2
                            color: cell.accentCol
                        }
                        Row {
                            x: 16
                            anchors.bottom: parent.bottom
                            anchors.bottomMargin: 16
                            spacing: 8

                            Repeater {
                                model: cell.isWallpaper ? [] : cell.modelData.ansi.slice(1, 7)

                                Rectangle {
                                    required property string modelData
                                    width: 18
                                    height: 18
                                    radius: 9
                                    color: modelData
                                }
                            }
                        }
                    }

                    Rectangle {
                        anchors.fill: parent
                        radius: 10
                        color: "transparent"
                        border.width: cell.busy ? 3 : cell.current ? 1 : 0
                        border.color: cell.busy ? Theme.accent : Qt.alpha(Theme.fg, 0.5)

                        SequentialAnimation on opacity {
                            running: cell.busy
                            loops: Animation.Infinite
                            alwaysRunToEnd: true
                            NumberAnimation { to: 0.4; duration: 120 }
                            NumberAnimation { to: 1.0; duration: 120 }
                        }
                    }

                    MouseArea {
                        anchors.fill: parent
                        onClicked: {
                            root.currentIndex = cell.index
                            root.apply(cell.modelData)
                        }
                    }
                }
            }
        }
    }

    // name of the centred scheme, under the carousel; a hint when nothing can be applied yet
    Text {
        x: card.x + root.pad
        y: carousel.y + root.carouselH + 10
        width: Math.max(0, card.width - 2 * root.pad)
        height: root.nameH
        horizontalAlignment: Text.AlignHCenter
        elide: Text.ElideRight
        text: root.wallpaperPath === "" ? "Pick a wallpaper first"
            : root.schemes[root.currentIndex].name
        color: Qt.alpha(Theme.fg, 0.7)
        font.family: Theme.fontFamilyAlt
        font.pixelSize: 12
        opacity: Math.max(0, (root.t - 0.5) * 2)
    }

    // the Wallpaper card: the palette maths is in services/WallpaperPalette.js, the same
    // as the wallpaper picker uses. This samples the image and hands the result on.
    Canvas {
        id: canvas
        x: 0
        y: 0
        width: 100
        height: 50
        visible: false

        onImageLoaded: {
            const url = "file://" + root.wallpaperPath
            if (root.deriving && isImageError(url))
                root.deriving = false
            else
                requestPaint()
        }

        onPaint: {
            if (!root.deriving)
                return
            const url = "file://" + root.wallpaperPath
            if (!isImageLoaded(url))
                return
            const ctx = getContext("2d")
            ctx.clearRect(0, 0, width, height)
            ctx.drawImage(url, 0, 0, width, height)
            const data = ctx.getImageData(0, 0, width, height).data
            unloadImage(url)
            root.deriving = false
            const result = Palette.derive(data)
            if (result)
                root.runWithWallpaper("wallpaper", result.palette, result.ansi, root.wallpaperPath)
        }
    }
}
