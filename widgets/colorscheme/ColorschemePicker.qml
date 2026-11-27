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

// The colorscheme picker: a list in the band that grows out of the bar pill, with
// "Wallpaper", whose colours are derived from the wallpaper in use, as the wallpaper picker
// does. The chosen row grows to show the scheme's colours over a wallpaper from its folder.
// Type to search, Up and Down (or Left and Right) move, Enter applies, Escape clears the
// search, then closes. Every scheme goes through the same wallpaper-theme script, so the
// files it writes stay in step; a fixed scheme hands it its own colours and the wallpaper
// shown behind its row, drawn from its folder in ~/.local/share/wallpapers, if it has one.
// The scheme in use is remembered in ~/.local/state/lumin/colorscheme-current, and the
// picker opens on it.
Item {
    id: root

    // a child of the origin bar's window (Bar.qml), so the band drops from the pill with no seam;
    // the bar's window takes keys and clicks for it
    visible: false
    anchors.fill: parent

    // the band: the search row, a rule, and a list of rows that scrolls when it is longer
    // than the band. The chosen row is taller than the others; the list shows four plain
    // rows and the chosen one.
    property int bandWidth: Math.min(460, root.width - 48)
    property int pad: 14
    property int headerH: 22
    property int rowH: 40
    property int rowGap: 6
    property int selH: 96
    property int listH: 4 * (rowH + rowGap) + selH
    property int bandHeight: pad + headerH + 14 + listH + pad

    readonly property string dirPath: Quickshell.env("HOME") + "/Pictures/Wallpapers"

    // where the card grows from: the pill, or the card of the panel that gave way to this one
    property real startW: PillState.pillWidth
    property real startH: PillState.pillHeight
    // 1 while the swatches show; they fade first when another panel takes the pill
    property real imagesOut: 1

    // 0 = the bar pill, 1 = the full band
    property real t: 0
    // a card closed back to the pill is hidden there: the elastic close reaches the pill early, and
    // a card left over it hid the bar's content until the morph finished
    onTChanged: if (morph.running && morph.to === 0 && t <= 0) visible = false

    readonly property var schemes: Schemes.SCHEMES
    // the search: typed straight away, there is no field to focus
    property string query: ""
    // what the row shows: all of them, or the matches of the query, best first
    readonly property var shown: query === "" ? schemes : Fuzzy.rank(schemes, query, s => s.name)
    // an index into `shown`
    property int currentIndex: 0
    onQueryChanged: currentIndex = 0

    // the scheme in use, mode, and the wallpaper the script is given. Read from the
    // files the pickers write, at start, so the first opening is not the one that loads them.
    property string currentId: ""
    property string wallpaperPath: ""
    property bool lightMode: Theme.light
    readonly property string stateFile: Quickshell.env("HOME") + "/.local/state/lumin/colorscheme-current"
    readonly property string wallpaperFile: Quickshell.env("HOME") + "/.local/state/lumin/wallpaper-current"
    readonly property string modeFile: Quickshell.env("HOME") + "/.local/state/lumin/colorscheme-mode"
    // set while the wallpaper is being sampled
    property bool deriving: false

    // the list's scroll: the chosen row centred, held inside the list's ends. Only the chosen
    // row is tall, so the rows above it are all rowH and its top is currentIndex * (rowH + rowGap).
    readonly property real contentH: shown.length * (rowH + rowGap) - rowGap + (selH - rowH)
    readonly property real scrollTarget: Math.max(0, Math.min(contentH - listH,
        currentIndex * (rowH + rowGap) + selH / 2 - listH / 2))
    property real scroll: scrollTarget
    Behavior on scroll { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }

    // on the scheme in use; "wallpaper" when none was remembered, as that is what a
    // wallpaper change leaves behind
    function focusCurrent() {
        query = ""
        const i = Schemes.indexOfId(currentId === "" ? "wallpaper" : currentId)
        currentIndex = i >= 0 ? i : 0
    }

    function imageFor(id) {
        const mode = root.lightMode ? "light" : "dark"
        return root.folderImages[id + "/" + mode]
            || root.folderImages[id]
            || root.wallpaperPath
    }

    // wallpaper-theme takes the wallpaper path first; without one nothing can be applied
    FileView {
        path: root.wallpaperFile
        watchChanges: true
        onFileChanged: reload()
        onLoaded: root.wallpaperPath = text().trim()
    }

    // watches the global light/dark mode file written by the settings drawer
    FileView {
        path: Quickshell.env("HOME") + "/.local/state/lumin/colorscheme-mode"
        watchChanges: true
        onFileChanged: reload()
        onLoaded: {
            root.lightMode = text().trim() === "light"
            Theme.light = root.lightMode
        }
        onLoadFailed: {
            root.lightMode = false
            Theme.light = false
        }
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
        if (visible) {
            lister.running = true
            keyHost.forceActiveFocus()
        }
    }

    // another panel took the pill, so this one gives way
    Connections {
        target: PillState
        function onOwnerChanged() {
            if (PillState.owner !== "colorschemes" && root.visible) {
                // a panel took the pill: hand our card over, or shrink back when nothing did
                if (PillState.owner !== "") root.giveWay()
                else root.close()
            }
        }
    }

    // the lock is about to take the screen: the picker closes back into the pill first
    Connections {
        target: PillState
        function onLockingChanged() {
            if (PillState.locking && root.visible)
                root.close()
        }
    }

    function openPicker() {
        focusCurrent()
        if (!PillState.claim("colorschemes"))
            return
        Sounds.play("open-colors")
        const from = PillState.takeOver()
        startW = from.w
        startH = from.h
        imagesOut = 1
        visible = true
        morph.stop()
        morph.from = root.t
        morph.to = 1
        morph.start()
    }

    // another panel took the pill: hand this card over and step aside at once, so the next
    // panel grows from the card's current size instead of from the pill
    function giveWay() {
        PillState.takeoverW = card.width
        PillState.takeoverH = card.height
        morph.stop()
        visible = false
        t = 0
        imagesOut = 1
    }

    function close() {
        if (visible)
            Sounds.play("close-colors")
        if (PillState.owner === "colorschemes")
            PillState.returning = true
        startW = PillState.pillWidth
        startH = PillState.pillHeight
        morph.stop()
        morph.from = root.t
        morph.to = 0
        morph.start()
    }

    function toggle() {
        if (visible && PillState.owner === "colorschemes") {
            close()
        } else {
            openPicker()
        }
    }
    function toggleMode(): void {
        root.lightMode = !root.lightMode
        Theme.light = root.lightMode

        const mode = root.lightMode ? "light" : "dark"

        Quickshell.execDetached([
            "sh", "-c",
            "printf '%s\\n' \"$1\" >| \"$2\"",
            "sh", mode, root.modeFile
        ])

        const id = root.currentId === "" ? "wallpaper" : root.currentId
        const index = Schemes.indexOfId(id)

        if (index >= 0)
            root.apply(Schemes.SCHEMES[index])
    }

    // qs ipc call colorschemes toggle
    IpcHandler {
        target: "colorschemes"

        function toggle(): void {
            root.toggle()
        }

        function toggleMode(): void {
            root.toggleMode()
        }
    }

    // grows the card from the pill (t=0) into the band (t=1); on the way back
    // it hides the window and releases the pill
    NumberAnimation {
        id: morph
        target: root
        property: "t"
        duration: PillState.morphMs
        easing.type: PillState.openEase
        easing.period: PillState.easePeriod
        onFinished: {
            if (root.t < 0.5) {
                root.visible = false
                if (PillState.owner === "colorschemes")
                    PillState.owner = ""
            }
        }
    }

    // One image per scheme folder (and mode subfolder), drawn when the picker opens.
    // It is the art behind the chosen row and the wallpaper that choosing the scheme sets,
    // so the row shows what it will apply. A scheme with no folder keeps the wallpaper in use.
    property var folderImages: ({})
    property var _found: []
    Component.onCompleted: lister.running = true
    Process {
        id: lister
        command: ["sh", "-c",
            "find -L \"" + root.dirPath + "\" -mindepth 2 -type f " +
            "\\( -iname '*.png' -o -iname '*.jpg' -o -iname '*.jpeg' \\)"]
        stdout: SplitParser {
            onRead: line => { if (line.trim() !== "") root._found.push(line.trim()) }
        }
        onRunningChanged: {
            if (running) {
                root._found = []
                return
            }
            const groups = {}
            for (const p of root._found) {
                const rel = p.substring(root.dirPath.length + 1)
                const parts = rel.split("/")
                // e.g. "gruvbox/dark" if nested in dark/light, otherwise just "gruvbox"
                const key = (parts.length >= 3 && (parts[1] === "dark" || parts[1] === "light"))
                    ? parts[0] + "/" + parts[1]
                    : parts[0]
                if (!groups[key]) groups[key] = []
                groups[key].push(p)
            }
            const picked = {}
            for (const key in groups)
                picked[key] = groups[key][Math.floor(Math.random() * groups[key].length)]
            root.folderImages = picked
        }
    }

    function apply(scheme) {
        if (!scheme || root.deriving || root.wallpaperPath === "")
            return
        if (scheme.id === "wallpaper") {
            root.deriving = true
            canvas.loadImage("file://" + root.wallpaperPath)
        } else {
            const v = Schemes.variantFor(scheme, root.lightMode)
            if (!v)
                return
            root.runWithWallpaper(scheme.id, v.palette, v.ansi, root.imageFor(scheme.id))
        }
    }

    function runWithWallpaper(id, palette, ansi, imgPath) {
        const at = Schemes.indexOfId(id)
        const scheme = at >= 0 ? Schemes.SCHEMES[at] : null
        const isLight = id === "wallpaper"
          ? root.lightMode
          : Schemes.isLightVariant(scheme, root.lightMode)
        const mode = isLight ? "--light" : "--dark"

        Quickshell.execDetached(
            ["wallpaper-theme", mode, imgPath].concat(palette).concat(ansi))
        Sounds.play("apply")

        root.currentId = id
        Quickshell.execDetached(["sh", "-c", "printf '%s\\n' \"$1\" >| \"$2\"",
                                 "sh", id, root.stateFile])

        // Update current wallpaper file so everything stays in sync
        Quickshell.execDetached(["sh", "-c", "printf '%s\\n' \"$1\" >| \"$2\"",
                                 "sh", imgPath, root.wallpaperFile])
        root.close()
    }

    // A held key repeats at the keyboard's rate, faster than the list can be
    // followed. Repeats are held to one step per repeatGap ms; a fresh press always steps.
    readonly property int repeatGap: 120
    property double lastMove: 0

    function moveBy(delta, repeat) {
        const now = Date.now()
        if (repeat && now - lastMove < repeatGap)
            return
        const next = currentIndex + delta
        if (next < 0 || next > shown.length - 1)
            return
        lastMove = now
        currentIndex = next
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
            } else if (event.key === Qt.Key_Up || event.key === Qt.Key_Left) {
                root.moveBy(-1, event.isAutoRepeat)
            } else if (event.key === Qt.Key_Down || event.key === Qt.Key_Right) {
                root.moveBy(1, event.isAutoRepeat)
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

        readonly property real fromW: root.startW
        readonly property real fromH: root.startH

        width: fromW + (root.bandWidth - fromW) * Math.max(0, root.t)
        height: fromH + (root.bandHeight - fromH) * Math.max(0, root.t)
        x: (root.width - width) / 2
        y: PillState.pillTop
        // under glass the outline behind it is the fill, so this must not paint over the blur
        color: UserSettings.liquidGlass ? "transparent" : Theme.bg
        radius: 26
    }

    // only the band takes clicks: the bar's window masks its input to this while the picker is open
    readonly property Item maskItem: outline

    // search row: the magnifier, what is typed (or what to type), and which row of how
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
            text: root.query !== "" ? root.query
                : root.wallpaperPath === "" ? "Pick a wallpaper first" : "Search themes…"
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

    // a thin rule under the search
    Rectangle {
        x: header.x
        y: header.y + root.headerH + 6
        width: header.width
        height: 1
        color: Qt.alpha(Theme.fg, 0.08)
        opacity: header.opacity
    }

    // the list, scrolled so the chosen row is centred. Fades in with the header.
    Item {
        id: strip
        x: card.x + root.pad
        y: card.y + root.pad + root.headerH + 14
        width: Math.max(0, card.width - 2 * root.pad)
        height: root.listH
        clip: true
        opacity: Math.min(root.imagesOut, Math.max(0, (root.t - 0.5) * 2))

        Text {
            visible: root.shown.length === 0
            anchors.centerIn: parent
            text: "Nothing matches"
            color: Qt.alpha(Theme.fg, 0.4)
            font.family: Theme.fontFamilySans
            font.pixelSize: 12
        }

        Column {
            y: -root.scroll
            width: parent.width
            spacing: root.rowGap

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
                    // Individual variant & background color for this specific scheme (falls back to Theme.bg)
                    readonly property var variant: Schemes.variantFor(modelData, root.lightMode)
                    
                    readonly property string schemeBg: isWallpaper || !variant ? Theme.bg : variant.palette[0]
                    // the wallpaper behind the row: the one in use for "Wallpaper", else its folder's
                    readonly property string art: isWallpaper ? root.wallpaperPath : root.imageFor(modelData.id)
                    readonly property int inset: 12
                    // 0 on a plain row, 1 on the chosen one, between while it grows or shrinks.
                    // Everything that moves is derived from it, so the height is the one animation.
                    readonly property real grow: Math.max(0, Math.min(1,
                        (height - root.rowH) / (root.selH - root.rowH)))

                    width: strip.width
                    height: current ? root.selH : root.rowH
                    Behavior on height { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }
                    radius: 12
                    color: Qt.alpha(Theme.fg, 0.06 * grow)

                    SequentialAnimation on opacity {
                        running: cell.busy
                        loops: Animation.Infinite
                        alwaysRunToEnd: true
                        NumberAnimation { to: 0.5; duration: 120 }
                        NumberAnimation { to: 1.0; duration: 120 }
                    }

                    // the art, across the whole row and shaded from the left like a shadow, so the
                    // name and colours stay readable on any wallpaper. The shade is the scheme's background colour
                    // at a falling alpha; only the chosen row loads an image.
                    // hidden rounded shape, used only to mask the art and its shade together: a
                    // gradient rectangle does not follow its own radius, so it cannot round itself
                    Item {
                        id: artMask
                        anchors.fill: parent
                        visible: false
                        layer.enabled: true

                        Rectangle {
                            anchors.fill: parent
                            radius: cell.radius
                            color: "white"
                        }
                    }
                    Item {
                        anchors.fill: parent
                        visible: cell.grow > 0 && cell.art !== ""
                        opacity: cell.grow
                        layer.enabled: true
                        layer.effect: MultiEffect {
                            maskEnabled: true
                            maskSource: artMask
                        }

                        Image {
                            anchors.fill: parent
                            source: cell.current && cell.art !== "" ? "file://" + cell.art : ""
                            sourceSize.width: 640
                            fillMode: Image.PreserveAspectCrop
                            asynchronous: true
                            opacity: status === Image.Ready ? 0.6 : 0
                            Behavior on opacity { NumberAnimation { duration: 160 } }
                        }
                        Rectangle {
                            anchors.fill: parent
                            gradient: Gradient {
                                orientation: Gradient.Horizontal
                                // Strong, opaque scheme background on the left for maximum readability, fading out to the right
                                GradientStop { position: 0.0; color: Qt.alpha(cell.schemeBg, 1.0) }
                                GradientStop { position: 0.5; color: Qt.alpha(cell.schemeBg, 0.95) }
                                GradientStop { position: 0.8; color: Qt.alpha(cell.schemeBg, 0.4) }
                                GradientStop { position: 1.0; color: Qt.alpha(cell.schemeBg, 0.0) }
                            }
                        }
                    }

                    // a plain row: the scheme's colour in a small tile. It goes as the row grows.
                    Rectangle {
                        x: cell.inset
                        y: (root.rowH - height) / 2
                        width: 28
                        height: 28
                        radius: 8
                        color: Qt.alpha(Theme.fg, 0.06)
                        opacity: 1 - cell.grow

                        Rectangle {
                            anchors.centerIn: parent
                            width: 12
                            height: 12
                            radius: 6
                            color: cell.isWallpaper || !cell.variant ? Theme.accent : cell.variant.palette[4]
                        }
                    }

                    // the name: beside the tile on a plain row, larger at the top left on the chosen one
                    Text {
                        x: (cell.inset + 28 + 12) * (1 - cell.grow) + cell.inset * cell.grow
                        y: ((root.rowH - height) / 2) * (1 - cell.grow) + 22 * cell.grow
                        text: cell.modelData.name
                        color: cell.current && cell.variant ? cell.variant.palette[2]
                            : cell.inUse ? Theme.accent
                            : cell.current ? Theme.fg : Qt.alpha(Theme.fg, 0.8)
                        font.family: Theme.fontFamilySans
                        font.pixelSize: Math.round(13 + 4 * cell.grow)
                        font.weight: cell.current ? Font.DemiBold : Font.Normal
                    }

                    // the six colours: small and at the right on a plain row; they grow and move
                    // under the name as the row is chosen. "Wallpaper" has none until applied.
                    Repeater {
                        model: cell.isWallpaper || !cell.variant ? [] : cell.variant.ansi.slice(1, 7)

                        Rectangle {
                            required property int index
                            required property string modelData
                            readonly property real d: 10 + 4 * cell.grow
                            width: d
                            height: d
                            radius: d / 2
                            color: modelData
                            x: (cell.width - cell.inset - 90 + index * 16) * (1 - cell.grow)
                                + (cell.inset + index * 22) * cell.grow
                            y: ((root.rowH - 10) / 2) * (1 - cell.grow) + (root.selH - 40) * cell.grow
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
            const result = Palette.derive(data, root.lightMode)
            if (result)
                root.runWithWallpaper("wallpaper", result.palette, result.ansi, root.wallpaperPath)
        }
    }
}
