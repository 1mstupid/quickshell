import QtQuick
import Quickshell
import Quickshell.Services.Pipewire
import "../../services"
import "../../services/menu"

// The control panel: a page of the focus notch. The gear at the right of the notch's
// header opens it from any page (and leaves it again), and so does
// `qs ipc call drawer toggle`; it has no tab of its own. Tiles for the quick switches,
// sliders for display and sound, and the power profile. Brightness and the profile only
// show on hardware that has them, and every item can be turned off in config.toml.
// The Wi-Fi and Bluetooth tiles switch on a tap and open their list from the
// arrow; the VPN tile opens its list. A list replaces the switches until Back.
// The arrow on Sound opens the per-app volumes. The notch sizes its card to this page:
// 340 wide, and as tall as the rows are.
Item {
    id: root

    readonly property int cardWidth: 340
    // the sides line up with the notch's header
    readonly property int pad: 18
    readonly property int bottomPad: 14
    readonly property int tileGap: 8
    readonly property int tileWidth: (cardWidth - 2 * pad - tileGap) / 2

    implicitWidth: cardWidth
    implicitHeight: col.implicitHeight + bottomPad
    width: implicitWidth
    height: implicitHeight

    readonly property bool showBrightness: UserSettings.brightness && Power.hasBacklight
    readonly property bool showProfile: UserSettings.powerProfile && Power.hasProfiles

    // "" for the switches, or "wifi", "bluetooth" or "vpn" for a list in their place
    property string view: ""
    readonly property bool inView: view !== ""

    // Escape from a list goes back to the switches; false when there is no list to leave,
    // and then the notch closes
    function leaveView(): bool {
        if (!inView)
            return false
        view = ""
        return true
    }

    // run once the notch has closed, so it is not in the shot
    readonly property var screenshotCommand: ["quickshell", "-p", Quickshell.shellDir, "ipc", "call", "screenshot", "capture"]

    // the per-app volume list under the volume slider; a right click on its icon toggles it
    property bool mixerOpen: false


    // streams only report their volume and properties once bound, so bind them
    // while the list is shown
    PwObjectTracker {
        objects: root.mixerOpen ? Volume.streams : []
    }

    // apps playing sound, by PipeWire's media class rather than the sink flag,
    // which does not say playback from capture; empty until the streams are bound
    readonly property var playback: Volume.streams.filter(n => n.properties["media.class"] === "Stream/Output/Audio")

    // so the brightness and profile rows are known before the first opening
    Component.onCompleted: Power.refresh()

    // brightness execution using ddcutil for absolute values
    property int pendingBrightness: -1

    function moveBrightness(v) {
        const p = Math.max(0, Math.min(100, Math.round(v * 100)))
        Power.brightness = p
        pendingBrightness = p
        if (!gate.running)
            gate.flush()
    }

    Timer {
        id: gate
        interval: 100
        function flush() {
            if (root.pendingBrightness >= 0) {
                // Execute ddcutil command for absolute brightness setting (VCP 10)
                Quickshell.execDetached(["sh", "-c", "ddcutil --display 1 setvcp 10 " + root.pendingBrightness])
                root.pendingBrightness = -1
            }
            start()
        }
        onTriggered: {
            if (root.pendingBrightness >= 0)
                flush()
        }
    }

    // the network tiles are read on demand, so keep them fresh while the page is up
    Timer {
        interval: 5000
        repeat: true
        running: root.visible
        onTriggered: Net.refreshState()
    }

    Timer {
        id: shot
        interval: 450
        onTriggered: Quickshell.execDetached(root.screenshotCommand)
    }

    // the lists and rows are read when the page comes up, not at every change
    onVisibleChanged: {
        if (visible) {
            Power.refresh()
            Net.refreshState()
            view = ""
            mixerOpen = false
        }
    }

    // a switch: a round badge with the icon, then name and state. The badge is what fills
    // while the switch is on; the tile itself stays quiet.
    component Tile: Rectangle {
        id: tile

        property string glyph
        property string title
        property string subtitle
        property bool active: false
        // with an arrow at the right that opens a list, apart from the tap
        property bool expandable: false
        signal clicked()
        signal expand()

        height: 48
        radius: height / 2
        color: Qt.alpha(Theme.fg, tileMouse.containsMouse ? 0.10 : 0.06)
        Behavior on color { ColorAnimation { duration: 120 } }

        // keyboard hint tools find a target by its role
        Accessible.role: Accessible.Button
        Accessible.name: tile.title

        Rectangle {
            id: badge
            anchors.left: parent.left
            anchors.leftMargin: 8
            anchors.verticalCenter: parent.verticalCenter
            width: 32
            height: 32
            radius: 16
            color: tile.active ? Theme.accent : Qt.alpha(Theme.fg, 0.10)
            Behavior on color { ColorAnimation { duration: 120 } }

            Text {
                anchors.centerIn: parent
                text: tile.glyph
                color: tile.active ? Theme.bg : Theme.fg
                font.family: Theme.fontFamily
                font.pixelSize: 16
            }
        }

        Column {
            anchors.left: badge.right
            anchors.leftMargin: 8
            anchors.right: parent.right
            anchors.rightMargin: tile.expandable ? 26 : 12
            anchors.verticalCenter: parent.verticalCenter
            spacing: 1

            Text {
                width: parent.width
                text: tile.title
                elide: Text.ElideRight
                color: Theme.fg
                font.family: Theme.fontFamily
                font.pixelSize: 11
                font.bold: true
            }
            Text {
                width: parent.width
                visible: tile.subtitle !== ""
                text: tile.subtitle
                elide: Text.ElideRight
                color: Qt.alpha(Theme.fg, 0.5)
                font.family: Theme.fontFamily
                font.pixelSize: 10
            }
        }

        MouseArea {
            id: tileMouse
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: {
                Sounds.play("toggle")
                tile.clicked()
            }
        }

        Text {
            visible: tile.expandable
            anchors.right: parent.right
            anchors.rightMargin: 10
            anchors.verticalCenter: parent.verticalCenter
            width: 16
            horizontalAlignment: Text.AlignHCenter
            text: "›"
            color: Qt.alpha(Theme.fg, 0.6)
            font.family: Theme.fontFamily
            font.pixelSize: 18
        }

        // above the tile's own area, so the arrow does not switch
        MouseArea {
            visible: tile.expandable
            anchors.top: parent.top
            anchors.bottom: parent.bottom
            anchors.right: parent.right
            width: 34
            cursorShape: Qt.PointingHandCursor
            onClicked: tile.expand()
        }
    }

    // a card with a name over a thick track, the icon inside it and the number at the
    // right; click or drag the track to set `value` (0 to 1). The icon is a button when
    // `iconActive` (mute); the arrow, when `expandable`, opens something under the card.
    component SliderRow: Rectangle {
        id: row

        property string title
        property string glyph
        property real value: 0
        property string readout
        // a muted look, for a muted output
        property bool dim: false
        property bool iconActive: false
        property bool expandable: false
        property bool expanded: false
        signal moved(real v)
        signal glyphClicked()
        signal glyphRightClicked()
        signal expand()

        height: 62
        radius: 16
        color: Qt.alpha(Theme.fg, 0.06)

        Text {
            id: rowTitle
            x: 12
            y: 8
            text: row.title
            color: Theme.fg
            font.family: Theme.fontFamily
            font.pixelSize: 11
            font.bold: true
        }

        Text {
            id: rowArrow
            visible: row.expandable
            anchors.right: parent.right
            anchors.rightMargin: 12
            y: 5
            width: 10
            horizontalAlignment: Text.AlignHCenter
            text: "›"
            rotation: row.expanded ? 90 : 0
            color: Qt.alpha(Theme.fg, 0.6)
            font.family: Theme.fontFamily
            font.pixelSize: 16
            Behavior on rotation { NumberAnimation { duration: 150; easing.type: Easing.OutCubic } }

            MouseArea {
                anchors.fill: parent
                anchors.margins: -6
                cursorShape: Qt.PointingHandCursor
                onClicked: row.expand()
            }
        }

        Text {
            anchors.right: row.expandable ? rowArrow.left : parent.right
            anchors.rightMargin: row.expandable ? 6 : 12
            y: 8
            text: row.readout
            color: Qt.alpha(Theme.fg, row.dim ? 0.4 : 0.6)
            font.family: Theme.fontFamilyAlt
            font.pixelSize: 11
            font.bold: true
        }

        Rectangle {
            id: track
            x: 8
            y: 28
            width: parent.width - 16
            height: 26
            radius: 13
            color: Qt.alpha(Theme.fg, 0.10)
            clip: true

            Rectangle {
                id: fill
                anchors.left: parent.left
                anchors.top: parent.top
                anchors.bottom: parent.bottom
                width: parent.width * Math.max(0, Math.min(1, row.dim ? 0 : row.value))
                radius: parent.radius
                color: Theme.accent
            }

            Text {
                id: rowIcon
                x: 8
                width: 20
                height: parent.height
                horizontalAlignment: Text.AlignHCenter
                verticalAlignment: Text.AlignVCenter
                text: row.glyph
                // dark on the fill, light on the bare track
                color: fill.width > 28 ? Theme.bg : Qt.alpha(Theme.fg, row.dim ? 0.5 : 0.8)
                font.family: Theme.fontFamily
                font.pixelSize: 15
            }
        }

        MouseArea {
            anchors.fill: track

            function set(x) {
                row.moved(Math.max(0, Math.min(1, x / width)))
            }
            onPressed: mouse => {
                Sounds.play("slide")
                set(mouse.x)
            }
            onPositionChanged: mouse => {
                if (pressed)
                    set(mouse.x)
            }
        }

        // over the track's, so the icon mutes and does not set the level
        MouseArea {
            enabled: row.iconActive
            x: track.x
            y: track.y
            width: 36
            height: track.height
            acceptedButtons: Qt.LeftButton | Qt.RightButton
            cursorShape: Qt.PointingHandCursor
            onClicked: mouse => {
                if (mouse.button === Qt.RightButton) {
                    row.glyphRightClicked()
                } else {
                    Sounds.play("toggle")
                    row.glyphClicked()
                }
            }
        }
    }

    // one app's volume: its name on the card; the icon mutes just that app
    component StreamRow: Column {
        id: stream

        required property var node
        readonly property var audio: node.audio

        spacing: 0

        SliderRow {
            width: parent.width
            title: stream.node.properties["application.name"] || stream.node.description || stream.node.name
            glyph: stream.audio.muted ? "󰝟" : "󰕾"
            value: Math.min(1, stream.audio.volume)
            readout: stream.audio.muted ? "MU" : Math.min(100, Math.round(stream.audio.volume * 100)).toString()
            dim: stream.audio.muted
            iconActive: true
            onMoved: v => {
                stream.audio.volume = v
                if (stream.audio.muted)
                    stream.audio.muted = false
            }
            onGlyphClicked: stream.audio.muted = !stream.audio.muted
        }
    }

    Column {
        id: col
        x: root.pad
        width: root.cardWidth - 2 * root.pad
        spacing: 12

        Grid {
            columns: 2
            spacing: root.tileGap
            visible: !root.inView

            Tile {
                width: root.tileWidth
                visible: UserSettings.wifi
                // without a wireless device this shows the wired link and only opens the list
                expandable: Net.hasWifi
                glyph: "󰖩"
                title: Net.hasWifi ? "Wi-Fi" : "Network"
                // a wireless card that is idle while the cable is up reads "Ethernet", not "Not connected"
                subtitle: Net.hasWifi
                    ? (Net.wifiOn ? (Net.wifiConn !== "" ? Net.wifiConn : (Net.wiredUp ? "Ethernet" : "Not connected")) : "Off")
                    : (Net.wiredUp ? "Ethernet" : "Disconnected")
                active: Net.hasWifi ? Net.wifiOn : Net.wiredUp
                onClicked: {
                    if (Net.hasWifi)
                        Net.toggleWifi()
                    else
                        root.view = "wifi"
                }
                onExpand: root.view = "wifi"
            }
            Tile {
                width: root.tileWidth
                visible: UserSettings.bluetooth && Net.btPresent
                expandable: true
                glyph: "󰂯"
                title: "Bluetooth"
                subtitle: Net.btOn ? "On" : "Off"
                active: Net.btOn
                onClicked: Net.toggleBluetooth()
                onExpand: root.view = "bluetooth"
            }
            // which profile to switch is a choice, so a tap opens the list
            Tile {
                width: root.tileWidth
                visible: UserSettings.vpn && Net.vpnCount > 0
                glyph: "󰦝"
                title: "VPN"
                subtitle: Net.vpnActive.length === 0 ? "Off"
                    : Net.vpnActive.length === 1 ? Net.vpnActive[0]
                    : Net.vpnActive.length + " active"
                active: Net.vpnActive.length > 0
                onClicked: root.view = "vpn"
            }

            Tile {
                width: root.tileWidth
                glyph: "󰂛"
                title: "Mute"
                subtitle: Notifications.muted ? "On" : "Off"
                active: Notifications.muted
                onClicked: Notifications.muted = !Notifications.muted
            }
            Tile {
                width: root.tileWidth
                visible: UserSettings.nightLight
                glyph: "󰖔"
                title: "Night light"
                subtitle: Power.nightLight ? "On" : "Off"
                active: Power.nightLight
                onClicked: Power.setNightLight(!Power.nightLight)
            }
            Tile {
                width: root.tileWidth
                visible: UserSettings.keepAwake
                glyph: "󰅶"
                title: "Keep awake"
                subtitle: Power.caffeine ? "On" : "Off"
                active: Power.caffeine
                onClicked: Power.setCaffeine(!Power.caffeine)
            }
            Tile {
                width: root.tileWidth
                visible: UserSettings.screenshot
                glyph: "󰄀"
                title: "Screenshot"
                onClicked: {
                    DrawerState.hide()
                    shot.restart()
                }
            }
            // Dark/Light mode toggle tile
            Tile {
                width: root.tileWidth
                glyph: Theme.light ? "󰖨" : "󰔎"
                title: "Theme"
                subtitle: Theme.light ? "Light" : "Dark"
                active: Theme.light

                onClicked: Quickshell.execDetached([
                    "quickshell", "-p", Quickshell.shellDir, "ipc", "call", "colorschemes", "toggleMode"
                ])
            }
        }

        Column {
            width: parent.width
            spacing: 8
            visible: !root.inView && (Volume.audio !== null || UserSettings.brightness)

            SliderRow {
                width: parent.width
                visible: UserSettings.brightness
                title: "Display"
                glyph: "󰃟"
                value: Power.brightness / 100
                readout: Power.brightness.toString()
                onMoved: v => root.moveBrightness(v)
            }

            SliderRow {
                width: parent.width
                visible: Volume.audio !== null
                title: "Sound"
                glyph: Volume.muted ? "󰝟" : "󰕾"
                value: Volume.audio ? Math.min(1, Volume.audio.volume) : 0
                readout: Volume.muted ? "MU" : Volume.volume.toString()
                dim: Volume.muted
                iconActive: true
                // the per-app volumes; a right click on the icon does the same
                expandable: true
                expanded: root.mixerOpen
                onMoved: v => {
                    Volume.audio.volume = v
                    if (Volume.audio.muted)
                        Volume.audio.muted = false
                }
                onGlyphClicked: Volume.audio.muted = !Volume.audio.muted
                onGlyphRightClicked: root.mixerOpen = !root.mixerOpen
                onExpand: root.mixerOpen = !root.mixerOpen
            }

            // per-app volumes; the panel eases taller to fit them
            Column {
                width: parent.width
                spacing: 8
                visible: root.mixerOpen && Volume.audio !== null

                Repeater {
                    model: root.playback

                    StreamRow {
                        required property var modelData
                        node: modelData
                        width: parent.width
                    }
                }

                Text {
                    visible: root.playback.length === 0
                    text: "No app is playing audio"
                    color: Qt.alpha(Theme.fg, 0.5)
                    font.family: Theme.fontFamily
                    font.pixelSize: 11
                }
            }
        }

        // power profile: one of three, the current one filled
        Row {
            visible: !root.inView && root.showProfile
            spacing: 4

            Repeater {
                model: [
                    { label: "Quiet", key: "power-saver" },
                    { label: "Balanced", key: "balanced" },
                    { label: "Performance", key: "performance" }
                ]

                Rectangle {
                    id: seg
                    required property var modelData
                    readonly property bool current: Power.profile === modelData.key

                    width: (col.width - 2 * 4) / 3
                    height: 28
                    radius: 14
                    color: current ? Theme.accent : Qt.alpha(Theme.fg, segMouse.containsMouse ? 0.10 : 0.06)
                    Behavior on color { ColorAnimation { duration: 120 } }

                    Text {
                        anchors.centerIn: parent
                        text: seg.modelData.label
                        color: seg.current ? Theme.bg : Theme.fg
                        font.family: Theme.fontFamily
                        font.pixelSize: 11
                        font.bold: seg.current
                    }

                    MouseArea {
                        id: segMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: Power.setProfile(seg.modelData.key)
                    }
                }
            }
        }

        // a network list, in place of the switches
        Column {
            visible: root.inView
            width: parent.width
            spacing: 6

            Rectangle {
                width: backRow.implicitWidth + 20
                height: 24
                radius: height / 2
                color: Qt.alpha(Theme.fg, backMouse.containsMouse ? 0.14 : 0.08)

                Row {
                    id: backRow
                    anchors.centerIn: parent
                    spacing: 6

                    Text {
                        text: "‹"
                        color: Theme.fg
                        font.family: Theme.fontFamily
                        font.pixelSize: 13
                    }
                    Text {
                        text: "Back"
                        color: Theme.fg
                        font.family: Theme.fontFamily
                        font.pixelSize: 11
                    }
                }

                MouseArea {
                    id: backMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.view = ""
                }
            }

            Item {
                width: parent.width
                height: 230

                // the lists keep their own 10 px margins, so the loader reaches past
                // the padding to line them up with the switches
                Loader {
                    x: -10
                    width: parent.width + 20
                    height: parent.height
                    active: root.inView
                    source: root.view === "wifi" ? "../menu/WifiPanel.qml"
                                            : root.view === "bluetooth" ? "../menu/BluetoothPanel.qml"
                                            : root.view === "vpn" ? "../menu/VpnPanel.qml"
                                            : ""
                }
            }
        }
    }
}
