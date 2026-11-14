import QtQuick
import QtQuick.Effects
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import "../../services"
import "../../services/WallpaperPalette.js" as Palette
import "../../widgets/colorscheme/Colorschemes.js" as Schemes 
import "../notch"
import "Fuzzy.js" as Fuzzy

// The wallpaper picker: a carousel of the images in ~/.local/share/wallpapers, in the
// band that grows out of the bar pill. Type to search the file names (fuzzy, in all the
// folders), Left and Right move, Enter applies, Escape clears the search, then closes. It
// opens on the wallpaper in use, which is remembered in ~/.local/xdg/config/wallpaper-current,
// and shows the folder that wallpaper is in: a colorscheme's folder (wallpapers/<scheme>/) after
// the scheme was chosen, since choosing one picks a wallpaper from it.
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

    // the panel, and the layout inside it: pad, header, gap, carousel, gap, name, pad
    // wide enough for five cards: the centre one and two each side. On a narrower
    // screen the outer ones are cut off by the carousel's clip.
    property int bandWidth: Math.min(1360, (root.screen ? root.screen.width : 1920) - 48)
    property int bandHeight: 260
    property int pad: 14
    property int headerH: 22
    property int carouselH: 170
    property int cardWidth: 300
    property int cardHeight: 170
    property int nameH: 18

    readonly property string dirPath: Quickshell.env("HOME") + "/.local/share/wallpapers"

    // carousel spacing: gap between neighbouring cards, and how fast they shrink
    property real gap: 24
    property real minScale: 0.55
    property real scaleStep: 0.15

    // 0 = the bar pill, 1 = the full band
    property real t: 0

    property var wallpapers: []
    // the search: typed straight away, there is no field to focus
    property string query: ""
    // the folder in view: the one the wallpaper in use is in ("wallpaper" is the top level).
    // Choosing a colorscheme picks a wallpaper from its folder, so this follows the scheme.
    readonly property string group: schemeOf(currentPath)
    // what is browsed: that folder, or everything when it has no wallpapers here
    function browse(current) {
        const g = schemeOf(current)
        const inGroup = wallpapers.filter(p => schemeOf(p) === g)
        return inGroup.length > 0 ? inGroup : wallpapers
    }
    readonly property var browsed: browse(currentPath)
    // whether that is a colorscheme's folder, and not the top level or everything
    readonly property bool inFolder: group !== "wallpaper" && wallpapers.some(p => schemeOf(p) === group)
    // what the carousel shows: the folder, or the matches of the query among all of them,
    // best first
    readonly property var shown: query === "" ? browsed : Fuzzy.rank(wallpapers, query, nameOf)
    // an index into `shown`
    property int currentIndex: 0
    onQueryChanged: currentIndex = 0

    // the wallpaper in use. It is written to a file when one is applied, so that it
    // survives a reboot and the picker opens on it and not on the first of the list.
    property string currentPath: ""
    readonly property string stateFile: Quickshell.env("HOME") + "/.local/xdg/config/wallpaper-current"
    // the colorscheme in use; applying a wallpaper makes it "wallpaper" or the subfolder name
    readonly property string schemeFile: Quickshell.env("HOME") + "/.local/xdg/config/colorscheme-current"
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

    // "/x/y/name.png" -> "name"
    function nameOf(path) {
        return path.split("/").pop().replace(/\.[^.]+$/, "")
    }

    // Extracts the parent folder name as the scheme if it's nested under wallpapers/
    function schemeOf(path) {
        const rel = path.substring(root.dirPath.length + 1)
        const parts = rel.split("/")
        if (parts.length > 1) {
            return parts[0] // e.g. ~/.local/share/wallpapers/catppuccin-mocha/bg.png -> "catppuccin-mocha"
        }
        return "wallpaper"
    }

    // the whole list, on the wallpaper in use
    function focusCurrent() {
        query = ""
        const list = browse(currentPath)
        const i = list.indexOf(currentPath)
        currentIndex = i >= 0 ? i : Math.min(currentIndex, Math.max(0, list.length - 1))
    }

    // the list and the wallpaper in use are read at start, so the first opening is not
    // the one that has to load them
    Component.onCompleted: lister.running = true

    FileView {
        path: root.stateFile
        watchChanges: true
        onFileChanged: reload()
        onLoaded: {
            root.currentPath = text().trim()
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
            if (PillState.owner !== "wallpapers" && root.visible)
                root.close()
        }
    }

    function openPicker() {
        focusCurrent()
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
            "find -L \"" + root.dirPath + "\" -type f " +
            "\\( -iname '*.png' -o -iname '*.jpg' -o -iname '*.jpeg' \\) | sort"]
        stdout: SplitParser {
            onRead: line => { if (line.trim() !== "") root._found.push(line.trim()) }
        }
        onRunningChanged: {
            if (running) {
                root._found = []
            } else {
                // a new array rebuilds every card and reloads every thumbnail, so the list
                // is only replaced when the folder changed, and the selection stays on its file
                if (root._found.join("\n") !== root.wallpapers.join("\n")) {
                    const keep = root.shown[root.currentIndex]
                    root.wallpapers = root._found
                    const at = root.shown.indexOf(keep)
                    root.currentIndex = at >= 0 ? at : 0
                }
                root.currentIndex = Math.min(root.currentIndex, Math.max(0, root.shown.length - 1))
                if (!root.visible)
                    root.focusCurrent()
                if (root.randomPending) {
                    root.randomPending = false
                    // inside the folder in view: another folder would change the scheme
                    const pool = root.browsed
                    if (pool.length > 0)
                        root.apply(pool[Math.floor(Math.random() * pool.length)])
                }
            }
        }
    }

    // A held key repeats at the keyboard's rate, faster than the carousel can be
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
                    // back to the folder in view, still on the wallpaper that was picked
                    const keep = root.shown[root.currentIndex]
                    root.query = ""
                    root.currentIndex = Math.max(0, root.browsed.indexOf(keep))
                } else {
                    root.close()
                }
            } else if (event.key === Qt.Key_Backspace) {
                root.query = root.query.slice(0, -1)
            } else if (event.key === Qt.Key_Left) {
                root.moveBy(-1, event.isAutoRepeat)
            } else if (event.key === Qt.Key_Right) {
                root.moveBy(1, event.isAutoRepeat)
            } else if (enter) {
                if (root.shown.length > 0)
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

    // header: the magnifier, what is typed (or what to type), then the folder in view and
    // shuffle. Fades in during the second half of the morph, like the carousel.
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
            anchors.right: actions.left
            anchors.rightMargin: 12
            anchors.verticalCenter: parent.verticalCenter
            text: root.query !== "" ? root.query : "Search wallpapers…"
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

        Row {
            id: actions
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            spacing: 12

            // the folder in view: a colorscheme's, or all of them while searching
            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: root.query !== "" ? "all" : root.inFolder ? root.group : ""
                color: Qt.alpha(Theme.fg, 0.5)
                font.family: Theme.fontFamilySans
                font.pixelSize: 12
            }
            Text {
                text: "󰒝"
                color: shuffleMa.containsMouse ? Theme.accent : Qt.alpha(Theme.fg, 0.6)
                font.family: Theme.fontFamily
                font.pixelSize: 16
                Behavior on color { ColorAnimation { duration: 120 } }

                MouseArea {
                    id: shuffleMa
                    anchors.fill: parent
                    anchors.margins: -6
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.applyRandom()
                }
            }
        }
    }

    // a thin rule between the search and the carousel
    Rectangle {
        x: header.x
        y: header.y + root.headerH + 6
        width: header.width
        height: 1
        color: Qt.alpha(Theme.fg, 0.08)
        opacity: header.opacity
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
            model: root.shown

            Item {
                id: cell
                required property int index
                required property string modelData

                // slots from the centre; fractional while the carousel is moving
                readonly property real d: cell.index - carousel.pos
                readonly property bool busy: root.applyingPath === modelData
                readonly property bool current: root.currentIndex === cell.index
                // only the cards near the centre load their image: a folder of large files
                // decoded all at once is what made the thumbnails slow to appear
                readonly property bool near: Math.abs(cell.index - root.currentIndex) <= 5

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
                    color: Qt.alpha(Theme.fg, 0.06)

                    // hidden rounded shape, used only to mask the thumbnail
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

                    Image {
                        anchors.fill: parent
                        source: cell.near ? "file://" + cell.modelData : ""
                        sourceSize.width: root.cardWidth * 2
                        fillMode: Image.PreserveAspectCrop
                        asynchronous: true
                        // fades in instead of popping in
                        opacity: status === Image.Ready ? 1 : 0
                        Behavior on opacity { NumberAnimation { duration: 160 } }
                        layer.enabled: true
                        layer.effect: MultiEffect {
                            maskEnabled: true
                            maskSource: thumbMask
                        }
                    }

                    Rectangle {
                        anchors.fill: parent
                        radius: 10
                        color: "transparent"
                        border.width: cell.busy ? 3 : cell.current ? 2 : 0
                        border.color: Theme.accent

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

    // under the carousel: the file name on the left, which of how many on the right
    Item {
        x: card.x + root.pad
        y: carousel.y + root.carouselH + 10
        width: Math.max(0, card.width - 2 * root.pad)
        height: root.nameH
        opacity: Math.max(0, (root.t - 0.5) * 2)

        Text {
            anchors.left: parent.left
            anchors.right: count.left
            anchors.rightMargin: 12
            anchors.verticalCenter: parent.verticalCenter
            elide: Text.ElideRight
            text: root.shown.length > 0 ? root.nameOf(root.shown[root.currentIndex])
                : root.query !== "" ? "Nothing matches" : ""
            color: Qt.alpha(Theme.fg, 0.7)
            font.family: Theme.fontFamilySans
            font.pixelSize: 12
        }
        Text {
            id: count
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            text: (root.shown.length > 0 ? root.currentIndex + 1 : 0) + "/" + root.shown.length
            color: Qt.alpha(Theme.fg, 0.4)
            font.family: Theme.fontFamilySans
            font.pixelSize: 11
        }
    }

    // Palette math lives in services/WallpaperPalette.js. This widget samples
    // the image, applies the result, and closes the picker.
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

    function finish(d) {
        let targetScheme = root.schemeOf(root.applyingPath)
        let result = null

        if (targetScheme !== "wallpaper") {
            const idx = Schemes.indexOfId(targetScheme)
            if (idx >= 0 && Schemes.SCHEMES[idx].palette) {
                result = Schemes.SCHEMES[idx]
            } else {
                // Subfolder name doesn't match a known scheme ID; fall back to dynamic extraction
                targetScheme = "wallpaper"
            }
        }

        if (!result) {
            result = Palette.derive(d)
            if (!result)
                return
        }

        // Always passes 25 arguments: 1 image path + 8 palette colors + 16 ansi colors
        Quickshell.execDetached(
            ["wallpaper-theme", root.applyingPath]
                .concat(result.palette).concat(result.ansi))

        // Remember current wallpaper for next boot
        root.currentPath = root.applyingPath
        Quickshell.execDetached(["sh", "-c", "printf '%s\\n' \"$1\" >| \"$2\"",
                                   "sh", root.applyingPath, root.stateFile])

        // Write out the active scheme ID (e.g. "gruvbox", "nord", or "wallpaper")
        Quickshell.execDetached(["sh", "-c", "printf '%s\\n' \"$1\" >| \"$2\"",
                                   "sh", targetScheme, root.schemeFile])

        root.applyingPath = ""
        root.close()
    }
}
