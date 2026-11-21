import QtQuick
import QtQuick.Effects
import "../../services"
import "../wallpaper/Fuzzy.js" as Fuzzy

// The Tray page of the focus notch: the favourite files as a carousel, like the wallpaper
// picker. Type to search their names (fuzzy), click a side card or the arrows to move, click
// the centre card or press Enter to open the file with xdg-open. The x takes the file off the
// tray. A file dropped on the page is kept. Favourites are not sent with the LocalSend queue.
Item {
    id: page

    readonly property int pad: 18
    readonly property int bottomH: 40
    readonly property int cardW: 160
    readonly property int cardH: 100
    readonly property real step: cardW * 0.8 + 10

    property string query: ""
    property int current: 0
    readonly property var shown: query.trim() === ""
        ? ShareService.favorites
        : Fuzzy.rank(ShareService.favorites, query, nameOf)

    function nameOf(path) {
        return path.split("/").pop()
    }

    function isImage(path) {
        return /\.(png|jpe?g|webp|gif|bmp)$/i.test(path)
    }

    function stepBy(delta) {
        if (shown.length > 0)
            current = Math.max(0, Math.min(shown.length - 1, current + delta))
    }

    function openCurrent() {
        if (shown.length > 0)
            ShareService.openFile(shown[current])
    }

    onQueryChanged: current = 0
    onShownChanged: current = Math.max(0, Math.min(current, shown.length - 1))

    // the search, typed straight in. Enter opens the centre file; Escape clears the search,
    // and with nothing typed it goes on to close the panel.
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
            onTextChanged: page.query = text

            Keys.onReturnPressed: page.openCurrent()
            Keys.onEnterPressed: page.openCurrent()
            Keys.onEscapePressed: event => {
                if (text !== "") {
                    text = ""
                    event.accepted = true
                }
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

    // a thin rule under the search, as the wallpaper picker has
    Rectangle {
        x: searchRow.x
        y: searchRow.y + searchRow.height + 6
        width: searchRow.width
        height: 1
        color: Qt.alpha(Theme.fg, 0.08)
    }

    // the carousel: each card is placed from the centre by its distance, so the cards
    // either side shrink and fade; the centre one is the file in focus
    Item {
        id: carousel
        x: page.pad
        y: 44
        width: page.width - 2 * page.pad
        height: page.height - y - page.bottomH
        clip: true

        // animated centre, so moving between cards glides
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

                width: page.cardW
                height: page.cardH
                x: carousel.width / 2 - width / 2 + d * page.step
                y: (carousel.height - height) / 2
                scale: Math.max(0.6, 1 - 0.25 * Math.abs(d))
                opacity: Math.abs(d) > 2.5 ? 0 : Math.max(0.3, 1 - 0.3 * Math.abs(d))
                visible: opacity > 0

                Rectangle {
                    anchors.fill: parent
                    radius: 10
                    color: Qt.alpha(Theme.fg, 0.06)
                    border.width: cell.focused ? 2 : 0
                    border.color: Theme.accent

                    // hidden rounded shape, used only to mask the picture
                    Item {
                        id: thumbMask
                        anchors.fill: parent
                        visible: false
                        layer.enabled: true
                        Rectangle { anchors.fill: parent; radius: 10; color: "white" }
                    }

                    Image {
                        anchors.fill: parent
                        visible: page.isImage(cell.modelData)
                        source: visible && cell.d > -3 && cell.d < 3 ? "file://" + cell.modelData : ""
                        sourceSize.width: page.cardW * 2
                        fillMode: Image.PreserveAspectCrop
                        asynchronous: true
                        layer.enabled: true
                        layer.effect: MultiEffect {
                            maskEnabled: true
                            maskSource: thumbMask
                        }
                    }

                    // a file that is not a picture: its glyph and name
                    Column {
                        anchors.centerIn: parent
                        visible: !page.isImage(cell.modelData)
                        spacing: 6
                        width: parent.width - 16

                        Text {
                            anchors.horizontalCenter: parent.horizontalCenter
                            text: "󰈔"
                            color: Qt.alpha(Theme.fg, 0.5)
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
                    }

                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            if (cell.focused)
                                page.openCurrent()
                            else
                                page.current = cell.index
                        }
                    }
                }
            }
        }

        // the cards dissolve into the panel at both ends, as in the wallpaper picker
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

        // arrows, when there is more than one file to move between
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

        // what the carousel says when there is nothing to show
        Text {
            visible: page.shown.length === 0
            anchors.centerIn: parent
            text: ShareService.favorites.length === 0 ? "drop files here to keep them" : "no matches"
            color: Qt.alpha(Theme.fg, 0.4)
            font.family: Theme.fontFamilySans
            font.pixelSize: 12
        }
    }

    // under the carousel: the name of the file in focus, its place, and the x to take it off
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
        Row {
            id: counter
            anchors.right: parent.right
            spacing: 10

            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: (page.current + 1) + " / " + page.shown.length
                color: Qt.alpha(Theme.fg, 0.5)
                font.family: Theme.fontFamilyNum
                font.pixelSize: 11
            }
            Text {
                id: removeGlyph
                anchors.verticalCenter: parent.verticalCenter
                text: "󰅖"
                color: Qt.alpha(Theme.fg, removeMouse.containsMouse ? 0.9 : 0.4)
                font.family: Theme.fontFamily
                font.pixelSize: 10
                MouseArea {
                    id: removeMouse
                    anchors.fill: parent
                    anchors.margins: -6
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: ShareService.removeFavorite(page.shown[page.current])
                }
            }
        }
    }

    // a file dropped anywhere on the page is kept on the tray
    DropArea {
        anchors.fill: parent
        keys: ["text/uri-list"]
        onDropped: drop => {
            ShareService.addFavorites(drop.urls)
            drop.accept(Qt.CopyAction)
        }
    }
}
