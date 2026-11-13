import QtQuick
import QtQuick.Effects
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import "../../services"
import "../../services/WallpaperPalette.js" as Palette
import "../notch"
import "../wallpaper/Fuzzy.js" as Fuzzy
import "Colorschemes.js" as Schemes

// The colorscheme picker: a row of cards in the band that grows out of the bar pill, with
// "Wallpaper", whose colours are derived from the wallpaper in use, as the wallpaper picker
// does. Type to search, Left and Right move, Enter applies, Escape clears the search, then
// closes. Every scheme goes through the same wallpaper-theme script, so the files it writes
// stay in step; a fixed scheme hands it its own colours and a random wallpaper from its
// folder in ~/.local/share/wallpapers, if it has one. The scheme in use is remembered in
// ~/.local/xdg/config/colorscheme-current, and the picker opens on it.
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

    // the band: the search row, a row of cards that scrolls when it is longer than the
    // band, and a hint under it
    property int bandWidth: Math.min(860, (root.screen ? root.screen.width : 1920) - 48)
    property int bandHeight: 190
    property int pad: 14
    property int headerH: 22
    property int cardWidth: 186
    property int cardHeight: 96
    property int cardGap: 12
    property int footH: 18

    readonly property string dirPath: Quickshell.env("HOME") + "/.local/share/wallpapers"

    // 0 = the bar pill, 1 = the full band
    property real t: 0

    readonly property var schemes: Schemes.SCHEMES
    // the search: typed straight away, there is no field to focus
    property string query: ""
    // what the row shows: all of them, or the matches of the query, best first
    readonly property var shown: query === "" ? schemes : Fuzzy.rank(schemes, query, s => s.name)
    // an index into `shown`
    property int currentIndex: 0
    onQueryChanged: currentIndex = 0

    // the scheme in use, and the wallpaper the script is given. Both are read from the
    // files the pickers write, at start, so the first opening is not the one that loads them.
    property string currentId: ""
    property string wallpaperPath: ""
    readonly property string stateFile: Quickshell.env("HOME") + "/.local/xdg/config/colorscheme-current"
    readonly property string wallpaperFile: Quickshell.env("HOME") + "/.local/xdg/config/wallpaper-current"
    // set while the wallpaper is being sampled
    property bool deriving: false

    // the row's scroll: the chosen card centred, held inside the row's ends. It uses the band's
    // full width and not the card's, which is still growing while it opens.
    readonly property real step: cardWidth + cardGap
    readonly property real innerW: bandWidth - 2 * pad
    readonly property real scrollTarget: Math.max(0,
        Math.min(shown.length * step - cardGap - innerW,
                 currentIndex * step + cardWidth / 2 - innerW / 2))
    property real scroll: scrollTarget
    Behavior on scroll { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }

    // on the scheme in use; "wallpaper" when none was remembered, as that is what a
    // wallpaper change leaves behind
    function focusCurrent() {
        query = ""
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
        if (!scheme || root.deriving || root.wallpaperPath === "")
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

    // Keyboard: letters go into the search; the arrows move, Enter applies. Esc clears
    // the search, and closes when there is none.
    Item {
        id: keyHost
        anchors.fill: parent
        focus: true

        Keys.onPressed: event => {
            const enter = event.key === Qt.Key_Return || event.key === Qt.Key_Enter
            if (event.key === Qt.Key_Escape) {
                if (root.query !== "") {
                    // back to the whole list, still on the scheme that was chosen
                    const keep = root.shown[root.currentIndex]
                    root.query = ""
                    root.currentIndex = Math.max(0, root.schemes.indexOf(keep))
                } else {
                    root.close()
                }
            } else if (event.key === Qt.Key_Backspace) {
                root.query = root.query.slice(0, -1)
            } else if (event.key === Qt.Key_Left) {
                if (root.currentIndex > 0)
                    root.currentIndex--
            } else if (event.key === Qt.Key_Right) {
                if (root.currentIndex < root.shown.length - 1)
                    root.currentIndex++
            } else if (enter) {
                root.apply(root.shown[root.currentIndex])
            } else if (event.text.length > 0 && event.text.charCodeAt(0) >= 0x20) {
                root.query += event.text
            } else {
                return
            }
            event.accepted = true
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

    // search row: the magnifier, what is typed (or what to type), and which card of how
    // many. Fades in during the second half of the morph, like the row.
    Item {
        id: header
        x: card.x + root.pad
        y: card.y + root.pad
        width: Math.max(0, card.width - 2 * root.pad)
        height: root.headerH
        opacity: Math.max(0, (root.t - 0.5) * 2)

        Text {
            id: glass
            anchors.verticalCenter: parent.verticalCenter
            text: "󰍉"
            color: Qt.alpha(Theme.fg, 0.5)
            font.family: Theme.fontFamily
            font.pixelSize: 16
        }
        Text {
            id: typed
            anchors.left: glass.right
            anchors.leftMargin: 12
            anchors.right: count.left
            anchors.rightMargin: 12
            anchors.verticalCenter: parent.verticalCenter
            text: root.query !== "" ? root.query : "Search themes…"
            elide: Text.ElideRight
            color: root.query !== "" ? Theme.fg : Qt.alpha(Theme.fg, 0.4)
            font.family: Theme.fontFamilySans
            font.pixelSize: 13
        }
        // the caret: after the text, or at the start of the placeholder
        Rectangle {
            x: typed.x + (root.query !== "" ? Math.min(typed.contentWidth, typed.width) + 1 : -1)
            anchors.verticalCenter: parent.verticalCenter
            width: 1
            height: 14
            color: Theme.accent
        }
        Text {
            id: count
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            text: (root.shown.length > 0 ? root.currentIndex + 1 : 0) + "/" + root.shown.length
            color: Qt.alpha(Theme.fg, 0.4)
            font.family: Theme.fontFamilyNum
            font.pixelSize: 11
        }
    }

    // the row of cards, scrolled so the chosen one is centred. Fades in with the header.
    Item {
        id: strip
        x: card.x + root.pad
        y: card.y + root.pad + root.headerH + 14
        width: Math.max(0, card.width - 2 * root.pad)
        height: root.cardHeight
        clip: true
        opacity: Math.max(0, (root.t - 0.5) * 2)

        Text {
            visible: root.shown.length === 0
            anchors.centerIn: parent
            text: "Nothing matches"
            color: Qt.alpha(Theme.fg, 0.4)
            font.family: Theme.fontFamilySans
            font.pixelSize: 12
        }

        Repeater {
            model: root.shown

              Rectangle {
                id: cell
                required property int index
                required property var modelData

                readonly property bool current: root.currentIndex === cell.index
                readonly property bool isWallpaper: modelData.id === "wallpaper"
                readonly property bool busy: isWallpaper && root.deriving
                // the scheme in use; "wallpaper" when none was remembered
                readonly property bool inUse: modelData.id === (root.currentId === "" ? "wallpaper" : root.currentId)

                x: cell.index * root.step - root.scroll
                width: root.cardWidth
                height: root.cardHeight
                radius: 10
                
                // CHANGED HERE: Use the first item of the palette array, or fall back to Theme.bg for wallpaper
                color: isWallpaper ? Theme.bg : modelData.palette[0]

                border.width: busy ? 3 : current ? 2 : 1
                border.color: current || busy ? Theme.accent : Qt.alpha(Theme.fg, 0.08)
                SequentialAnimation on opacity {
                    running: cell.busy
                    loops: Animation.Infinite
                    alwaysRunToEnd: true
                    NumberAnimation { to: 0.5; duration: 120 }
                    NumberAnimation { to: 1.0; duration: 120 }
                }

                // a fixed scheme: its six colours
                Row {
                    visible: !cell.isWallpaper
                    anchors.horizontalCenter: parent.horizontalCenter
                    y: 24
                    spacing: 8

                    Repeater {
                        model: cell.isWallpaper ? [] : cell.modelData.ansi.slice(1, 7)

                        Rectangle {
                            required property string modelData
                            width: 14
                            height: 14
                            radius: 7
                            color: modelData
                        }
                    }
                }

                // the wallpaper card: the wallpaper its colours come from
                Item {
                    visible: cell.isWallpaper
                    anchors.horizontalCenter: parent.horizontalCenter
                    y: 14
                    width: 116
                    height: 38

                    // hidden rounded shape, used only to mask the thumbnail
                    Item {
                        id: thumbMask
                        anchors.fill: parent
                        visible: false
                        layer.enabled: true

                        Rectangle {
                            anchors.fill: parent
                            radius: 6
                            color: "white"
                        }
                    }
                    Image {
                        anchors.fill: parent
                        source: cell.isWallpaper && root.wallpaperPath !== "" ? "file://" + root.wallpaperPath : ""
                        sourceSize.width: 232
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
                }

                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    anchors.bottom: parent.bottom
                    anchors.bottomMargin: 16
                    width: parent.width - 20
                    horizontalAlignment: Text.AlignHCenter
                    elide: Text.ElideRight
                    text: cell.modelData.name
                    
                    // CHANGED HERE: Use the scheme's foreground color (palette[2]), or Theme.fg for wallpaper
                    color: cell.isWallpaper 
                        ? (cell.current ? Theme.fg : Qt.alpha(Theme.fg, 0.8)) 
                        : (cell.current ? cell.modelData.palette[2] : Qt.alpha(cell.modelData.palette[2], 0.7))
                        
                    font.family: Theme.fontFamilySans
                    font.pixelSize: 12
                    font.weight: cell.current ? Font.DemiBold : Font.Normal
                }

                // the scheme in use
                Rectangle {
                    visible: cell.inUse
                    anchors.top: parent.top
                    anchors.right: parent.right
                    anchors.margins: 10
                    width: 6
                    height: 6
                    radius: 3
                    color: Theme.accent
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

    // under the row: what is missing before anything can be applied, and the key to apply
    Item {
        x: card.x + root.pad
        y: strip.y + root.cardHeight + 10
        width: Math.max(0, card.width - 2 * root.pad)
        height: root.footH
        opacity: Math.max(0, (root.t - 0.5) * 2)

        Text {
            anchors.verticalCenter: parent.verticalCenter
            visible: root.wallpaperPath === ""
            text: "Pick a wallpaper first"
            color: Qt.alpha(Theme.fg, 0.5)
            font.family: Theme.fontFamilySans
            font.pixelSize: 11
        }
        Text {
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            text: "Enter to apply"
            color: Qt.alpha(Theme.fg, 0.4)
            font.family: Theme.fontFamilySans
            font.pixelSize: 11
        }
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
