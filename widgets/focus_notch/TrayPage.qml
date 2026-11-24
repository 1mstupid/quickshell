import QtQuick
import QtQuick.Effects
import Quickshell
import Quickshell.Io
import "../../services"
import "../wallpaper/Fuzzy.js" as Fuzzy
import "TrayGlyphs.js" as TrayGlyphs
import "TraySort.js" as TraySort

FocusScope {
    id: page
    focus: true

    readonly property alias searching: search.activeFocus

    DropArea {
        anchors.fill: parent
        keys: ["text/uri-list"]
        onDropped: drop => {
            if (page.dir !== "")
                return
            ShareService.addFavorites(drop.urls)
            Sounds.play("done")
            drop.accept(Qt.CopyAction)
        }
    }

    readonly property int pad: 18
    readonly property int bottomH: 40
    readonly property int cardW: 160
    readonly property int cardH: 100
    readonly property real step: cardW * 0.8 + 10

    property string query: ""
    property int current: 0
    property int sortIndex: 0
    readonly property string sortMode: TraySort.MODES[sortIndex].key
    property var trail: []
    readonly property string dir: trail.length > 0 ? trail[trail.length - 1] : ""
    property var children: []
    property var childInfo: ({})
    property string listedFor: ""

    function infoOf(path) {
        return (dir === "" ? ShareService.info[path] : childInfo[path]) ?? {}
    }

    function isFolder(path) {
        return infoOf(path).dir === true
    }

    function isMissing(path) {
        return dir === "" && ShareService.missing[path] === true
    }

    readonly property var source: dir === "" ? ShareService.favorites : children
    readonly property var ordered: TraySort.sort(source, sortMode, infoOf, nameOf)
    readonly property var shown: query.trim() === "" ? ordered : Fuzzy.rank(ordered, query, nameOf)

    function nameOf(path) {
        return path.split("/").pop()
    }

    function isImage(path) {
        return /\.(png|jpe?g|webp|gif|bmp)$/i.test(path)
    }

    function stepTo(index) {
        if (shown.length > 0) {
            const next = Math.max(0, Math.min(shown.length - 1, index))
            if (next !== current) {
                current = next
                Sounds.play("slide")
            }
        }
    }

    function stepBy(delta) {
        if (shown.length > 0) {
            const next = Math.max(0, Math.min(shown.length - 1, current + delta))
            if (next !== current) {
                current = next
                Sounds.play("slide")
            }
        }
    }

    readonly property string thumbDir: Quickshell.env("HOME") + "/.cache/lumin/tray-thumbs"
    property var thumbReady: ({})
    property var thumbQueue: []

    function thumbUrl(path) {
        return "file://" + thumbDir + "/" + TrayGlyphs.thumbName(path)
    }

    function queueThumb(path) {
        if (thumbReady[path] === true || thumbQueue.indexOf(path) >= 0 || thumbProc.thumbFor === path)
            return
        thumbQueue = thumbQueue.concat([path])
        runThumbs()
    }

    function runThumbs() {
        if (thumbProc.running || thumbQueue.length === 0)
            return
        const path = thumbQueue[0]
        thumbQueue = thumbQueue.slice(1)
        thumbProc.thumbFor = path
        const frame = TrayGlyphs.isAudio(path) ? "-an -frames:v 1" : "-ss 1 -frames:v 1"
        thumbProc.command = ["sh", "-c",
            "mkdir -p \"$(dirname \"$2\")\" && ffmpeg -v error -n -i \"$1\" " + frame + " -vf scale=320:-2 \"$2\"",
            "sh", path, thumbDir + "/" + TrayGlyphs.thumbName(path)]
        thumbProc.running = true
    }

    Process {
        id: thumbProc
        property string thumbFor: ""
        onExited: {
            const done = Object.assign({}, page.thumbReady)
            done[thumbFor] = true
            page.thumbReady = done
            page.runThumbs()
        }
    }

    // the search has let go of the keys: the notch's key handler takes them back
    signal searchLeft()

    // "/" or a typed letter opens the search, with that letter already in it
    function startSearch(typed) {
        search.forceActiveFocus()
        if (typed)
            search.text += typed
    }

    function openCurrent() {
        if (shown.length === 0)
            return
        current = Math.min(current, shown.length - 1)
        const p = shown[current]
        if (isFolder(p)) {
            Sounds.play("open")
            enter(p)
        } else {
            Sounds.play("launch")
            ShareService.openFile(p)
        }
    }

    function enterCurrent() {
        if (shown.length > 0 && isFolder(shown[current])) {
            Sounds.play("open")
            enter(shown[current])
        }
    }

    function removeCurrent() {
        if (dir !== "" || shown.length === 0)
            return
        Sounds.play("toggle")
        ShareService.removeFavorite(shown[current])
    }

    function cycleSort() {
        Sounds.play("slide")
        sortIndex = (sortIndex + 1) % TraySort.MODES.length
        current = 0
    }

    function enter(path) {
        search.text = ""
        trail = trail.concat([path])
        current = 0
        refreshListing()
    }

    function up() {
        if (trail.length === 0)
            return
        search.text = ""
        trail = trail.slice(0, -1)
        current = 0
        refreshListing()
        Sounds.play("page")
    }

    function jump(depth) {
        if (depth >= trail.length)
            return
        Sounds.play("page")
        search.text = ""
        trail = trail.slice(0, depth)
        current = 0
        refreshListing()
    }

    function refreshListing() {
        if (dir === "") {
            children = []
            childInfo = ({})
            return
        }
        listedFor = dir
        listProc.running = false
        listProc.command = ["timeout", "3", "find", dir, "-mindepth", "1", "-maxdepth", "1",
            "-not", "-name", ".*", "-printf", "%y\t%s\t%T@\t%p\n"]
        listProc.running = true
    }

    Process {
        id: listProc
        stdout: StdioCollector {
            onStreamFinished: {
                if (page.listedFor !== page.dir)
                    return
                var info = {}
                var paths = []
                for (const line of text.split("\n")) {
                    const a = line.indexOf("\t")
                    const b = a < 0 ? -1 : line.indexOf("\t", a + 1)
                    const c = b < 0 ? -1 : line.indexOf("\t", b + 1)
                    if (c < 0)
                        continue
                    const path = line.slice(c + 1)
                    info[path] = {
                        dir: line.slice(0, a) === "d",
                        size: parseInt(line.slice(a + 1, b)),
                        mtime: parseFloat(line.slice(b + 1, c))
                    }
                    paths.push(path)
                }
                page.childInfo = info
                page.children = paths
            }
        }
    }

    Keys.onPressed: event => {
        if (search.activeFocus)
            return

        if (event.key === Qt.Key_Left) {
            page.stepBy(-1)
            event.accepted = true
        } else if (event.key === Qt.Key_Right) {
            page.stepBy(1)
            event.accepted = true
        } else if (event.key === Qt.Key_Up) {
            page.up()
            event.accepted = true
        } else if (event.key === Qt.Key_Down || event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
            page.openCurrent()
            event.accepted = true
        } else if (event.key === Qt.Key_Home) {
            page.stepTo(0)
            event.accepted = true
        } else if (event.key === Qt.Key_End) {
            page.stepTo(page.shown.length - 1)
            event.accepted = true
        } else if (event.key === Qt.Key_S && event.modifiers === Qt.NoModifier) {
            page.cycleSort()
            event.accepted = true
        } else if (event.key === Qt.Key_X && event.modifiers === Qt.NoModifier) {
            page.removeCurrent()
            event.accepted = true
        } else if (event.key === Qt.Key_Slash || (event.text.length === 1 && event.modifiers === Qt.NoModifier)) {
            search.forceActiveFocus()
            if (event.key !== Qt.Key_Slash)
                search.text += event.text
            event.accepted = true
        }
    }

    Item {
        id: searchRow
        x: page.pad
        y: 12
        width: page.width - 2 * page.pad
        height: 22

        TextInput {
            id: search
            anchors.fill: parent
            clip: true
            selectByMouse: true
            color: Theme.fg
            selectionColor: Theme.accent
            selectedTextColor: Theme.bg
            font.family: Theme.fontFamilySans
            font.pixelSize: 12

            onTextChanged: {
                page.query = text
                page.current = 0
                if (UserSettings.sounds) {
                    Quickshell.execDetached(["paplay", "--volume=" + Sounds.volume, Quickshell.shellDir + "/assets/reusables/input/type.wav"])
                }
            }

            Keys.onReturnPressed: page.openCurrent()
            Keys.onEnterPressed: page.openCurrent()
            Keys.onEscapePressed: event => {
                if (text !== "") {
                    text = ""
                    Sounds.play("toggle")
                } else {
                    search.focus = false
                    page.searchLeft()
                    Sounds.play("page")
                }
                event.accepted = true
            }
        }

        Text {
            visible: search.text === ""
            anchors.verticalCenter: parent.verticalCenter
            text: "Search the tray"
            color: Qt.alpha(Theme.fg, 0.4)
            font.family: Theme.fontFamilySans
            font.pixelSize: 12
        }
    }

    Item {
        id: crumbRow
        x: page.pad
        y: 46
        width: page.width - 2 * page.pad
        height: 14

        Row {
            id: crumbs
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            spacing: 6

            Text {
                visible: page.trail.length > 0
                text: "󰅁 up"
                color: upMouse.containsMouse ? Theme.fg : Qt.alpha(Theme.fg, 0.5)
                font.family: Theme.fontFamilySans
                font.pixelSize: 11
                MouseArea {
                    id: upMouse
                    anchors.fill: parent
                    anchors.margins: -6
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: page.up()
                }
            }

            Text {
                text: "Tray"
                color: page.trail.length === 0 ? Theme.fg : Qt.alpha(Theme.fg, 0.5)
                font.family: Theme.fontFamilySans
                font.pixelSize: 11
                MouseArea {
                    anchors.fill: parent
                    anchors.margins: -4
                    cursorShape: Qt.PointingHandCursor
                    onClicked: page.jump(0)
                }
            }
            Repeater {
                model: page.trail

                Row {
                    spacing: 6

                    Text {
                        text: "›"
                        color: Qt.alpha(Theme.fg, 0.3)
                        font.family: Theme.fontFamilySans
                        font.pixelSize: 11
                    }
                    Text {
                        text: page.nameOf(modelData)
                        color: index === page.trail.length - 1 ? Theme.fg : Qt.alpha(Theme.fg, 0.5)
                        font.family: Theme.fontFamilySans
                        font.pixelSize: 11
                        MouseArea {
                            anchors.fill: parent
                            anchors.margins: -4
                            cursorShape: Qt.PointingHandCursor
                            onClicked: page.jump(index + 1)
                        }
                    }
                }
            }
        }

        Text {
            id: sortLabel
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            text: "sort: " + TraySort.MODES[page.sortIndex].label
            color: sortMouse.containsMouse ? Theme.fg : Qt.alpha(Theme.fg, 0.5)
            font.family: Theme.fontFamilySans
            font.pixelSize: 11
            MouseArea {
                id: sortMouse
                anchors.fill: parent
                anchors.margins: -4
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: page.cycleSort()
            }
        }
    }

    Item {
        id: carousel
        x: page.pad
        y: 68
        width: page.width - 2 * page.pad
        height: page.height - y - page.bottomH
        clip: true

        property real pos: page.current
        Behavior on pos {
            NumberAnimation { duration: 220; easing.type: Easing.OutCubic }
        }

        Repeater {
            model: page.shown

            Item {
                id: cell
                required property int index
                required property string modelData

                readonly property real d: cell.index - carousel.pos
                readonly property bool focused: page.current === cell.index
                readonly property bool isDir: page.isFolder(cell.modelData)
                readonly property bool picture: !cell.isDir && page.isImage(cell.modelData)
                readonly property bool clip: !cell.isDir && TrayGlyphs.isMedia(cell.modelData)
                readonly property bool near: Math.abs(cell.d) < 3
                readonly property bool thumbed: page.thumbReady[cell.modelData] === true

                onNearChanged: if (cell.near && cell.clip && !cell.thumbed) page.queueThumb(cell.modelData)
                Component.onCompleted: if (cell.near && cell.clip && !cell.thumbed) page.queueThumb(cell.modelData)
                readonly property bool missing: page.isMissing(cell.modelData)

                width: page.cardW
                height: page.cardH
                x: carousel.width / 2 - width / 2 + d * page.step
                y: (carousel.height - height) / 2
                scale: Math.max(0.6, 1 - 0.25 * Math.abs(d))
                opacity: Math.abs(d) > 2.5 ? 0 : Math.max(0.3, 1 - 0.3 * Math.abs(d))
                visible: opacity > 0

                Item {
                    id: ghost
                    width: cell.width
                    height: cell.height
                    Drag.active: cardMa.drag.active
                    Drag.dragType: Drag.Automatic
                    Drag.supportedActions: Qt.CopyAction | Qt.MoveAction
                    Drag.mimeData: ({ "text/uri-list": ShareService.fileUrl(cell.modelData) })

                    ParallelAnimation {
                        id: snapBack
                        NumberAnimation { target: ghost; property: "x"; to: 0; duration: 180; easing.type: Easing.OutCubic }
                        NumberAnimation { target: ghost; property: "y"; to: 0; duration: 180; easing.type: Easing.OutCubic }
                    }

                    Rectangle {
                        anchors.fill: parent
                        radius: 10
                        color: Qt.alpha(Theme.fg, 0.06)
                        opacity: cell.missing ? 0.45 : 1

                        Item {
                            id: thumbMask
                            anchors.fill: parent
                            visible: false
                            layer.enabled: true
                            Rectangle { anchors.fill: parent; radius: 10; color: "white" }
                        }

                        Image {
                            id: thumbImg
                            anchors.fill: parent
                            visible: cell.picture || cell.clip
                            source: cell.picture && cell.near ? "file://" + cell.modelData
                                : cell.clip && cell.thumbed ? page.thumbUrl(cell.modelData)
                                : ""
                            sourceSize.width: page.cardW * 2
                            fillMode: Image.PreserveAspectCrop
                            asynchronous: true
                            layer.enabled: true
                            layer.effect: MultiEffect {
                                maskEnabled: true
                                maskSource: thumbMask
                            }
                        }

                        Column {
                            anchors.centerIn: parent
                            visible: !cell.picture && thumbImg.status !== Image.Ready
                            spacing: 6
                            width: parent.width - 16

                            Text {
                                anchors.horizontalCenter: parent.horizontalCenter
                                text: TrayGlyphs.glyphFor(cell.modelData, cell.isDir)
                                color: cell.isDir ? Theme.accent : Qt.alpha(Theme.fg, 0.55)
                                font.family: Theme.fontFamily
                                font.pixelSize: 28
                            }
                            Text {
                                width: parent.width
                                horizontalAlignment: Text.AlignHCenter
                                text: page.nameOf(cell.modelData)
                                elide: Text.ElideMiddle
                                color: Qt.alpha(Theme.fg, 0.8)
                                font.family: Theme.fontFamilySans
                                font.pixelSize: 11
                            }
                            Text {
                                visible: cell.missing
                                anchors.horizontalCenter: parent.horizontalCenter
                                text: "missing"
                                color: Qt.alpha(Theme.fg, 0.5)
                                font.family: Theme.fontFamilySans
                                font.pixelSize: 9
                            }
                        }

                        MouseArea {
                            id: cardMa
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            drag.target: cell.focused ? ghost : null
                            onPressed: snapBack.stop()
                            onReleased: snapBack.restart()
                            onClicked: {
                                if (cell.isDir && cell.focused) {
                                    Sounds.play("open")
                                    page.enter(cell.modelData)
                                } else if (cell.focused) {
                                    page.openCurrent()
                                } else {
                                    Sounds.play("slide")
                                    page.current = cell.index
                                }
                            }
                        }
                    }
                }
            }
        }

        Rectangle {
            anchors.left: parent.left
            anchors.top: parent.top
            anchors.bottom: parent.bottom
            width: parent.width * 0.2
            gradient: Gradient {
                orientation: Gradient.Horizontal
                GradientStop { position: 0.0; color: Qt.alpha(Theme.bg, 0.95) }
                GradientStop { position: 1.0; color: Qt.alpha(Theme.bg, 0) }
            }
        }
        Rectangle {
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.bottom: parent.bottom
            width: parent.width * 0.2
            gradient: Gradient {
                orientation: Gradient.Horizontal
                GradientStop { position: 0.0; color: Qt.alpha(Theme.bg, 0) }
                GradientStop { position: 1.0; color: Qt.alpha(Theme.bg, 0.95) }
            }
        }

        Text {
            visible: page.shown.length > 1 && page.current > 0
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            anchors.leftMargin: 4
            text: "󰅁"
            color: Qt.alpha(Theme.fg, 0.6)
            font.family: Theme.fontFamily
            font.pixelSize: 16
            MouseArea {
                anchors.fill: parent
                anchors.margins: -6
                cursorShape: Qt.PointingHandCursor
                onClicked: page.stepBy(-1)
            }
        }

        Text {
            visible: page.shown.length > 1 && page.current < page.shown.length - 1
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            anchors.rightMargin: 4
            text: "󰅂"
            color: Qt.alpha(Theme.fg, 0.6)
            font.family: Theme.fontFamily
            font.pixelSize: 16
            MouseArea {
                anchors.fill: parent
                anchors.margins: -6
                cursorShape: Qt.PointingHandCursor
                onClicked: page.stepBy(1)
            }
        }

        Text {
            visible: page.shown.length === 0
            anchors.centerIn: parent
            text: page.query.trim() !== "" ? "no matches"
                : page.dir === "" ? "drop files here to keep them"
                : "this folder is empty"
            color: Qt.alpha(Theme.fg, 0.4)
            font.family: Theme.fontFamilySans
            font.pixelSize: 12
        }
    }

    Item {
        x: page.pad
        y: carousel.y + carousel.height + 6
        width: page.width - 2 * page.pad
        height: 18
        visible: page.shown.length > 0

        Text {
            anchors.left: parent.left
            anchors.right: counter.left
            anchors.rightMargin: 10
            text: page.shown.length > 0 ? page.nameOf(page.shown[page.current]) : ""
            elide: Text.ElideMiddle
            color: Theme.fg
            font.family: Theme.fontFamilySans
            font.pixelSize: 12
        }
        Text {
            id: counter
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            text: (page.current + 1) + " / " + page.shown.length
            color: Qt.alpha(Theme.fg, 0.5)
            font.family: Theme.fontFamilyNum
            font.pixelSize: 11
        }
    }
}
