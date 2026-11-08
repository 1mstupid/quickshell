import QtQuick
import Quickshell
import Quickshell.Wayland
import "../../services"
import "../../services/menu"
import "../notch"

// The focus notch: the bar's center pill grows into the pomodoro and, on a
// click, into today's tasks. Hover the pill and it widens into a strip with the
// session ring, the time left and pause and stop. Click the strip (or run
// `qs ipc call focusnotch toggle`) and it opens further: the pomodoro card on
// the left, what is left to do today from todo.md on the right, where a click
// on a circle ticks the task. The control icon opens the control drawer, since
// the strip hides the clock that used to do that. The strip closes when the
// pointer leaves it; the open panel closes on Escape or a click outside.
PanelWindow {
    id: root

    screen: PillState.originScreen
    visible: false

    anchors {
        top: true
        left: true
        right: true
    }
    implicitHeight: PillState.pillTop + openH + 12

    color: "transparent"
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: root.stage === "open" ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None
    WlrLayershell.namespace: "quickshell-focusnotch"

    // the strip only takes input on the card, so the screen below stays usable;
    // the open panel also takes the band around it, to catch a click outside
    mask: Region { item: root.stage === "open" ? catcher : card }

    // ── Geometry ───────────────────────────────────────────────────────────
    readonly property int hoverW: 480
    readonly property int hoverH: 78
    readonly property int openW: 560
    readonly property int openH: 262
    readonly property int maxRows: 5

    // "" closed, "hover" the strip, "open" the full panel
    property string stage: ""
    // after a close the pointer has to leave the pill before it can open the strip again
    property bool armed: true
    onStageChanged: if (stage === "open") keyHost.forceActiveFocus()
    // 0 = the bar pill, 1 = the strip; 0 = the strip, 1 = the full panel
    property real grow: 0
    property real expand: 0

    // ── Data ───────────────────────────────────────────────────────────────
    readonly property int pomos: AppUsage.pomodoros(AppUsage.dayKey(), AppUsage.revision)
    readonly property int setFilled: Pomodoro.phase === "long" ? 4 : pomos % 4
    readonly property string phaseLabel: Pomodoro.phase === "work" ? "FOCUS"
        : Pomodoro.phase === "short" ? "SHORT BREAK" : "LONG BREAK"
    readonly property real ringFraction: Pomodoro.done ? 1 : Pomodoro.active ? Pomodoro.fraction : 0
    readonly property int ringMinutes: Pomodoro.active ? Math.ceil(Pomodoro.remaining / 60) : Pomodoro.minutes
    readonly property string readout: Pomodoro.done ? "00:00"
        : fmt(Pomodoro.active ? Pomodoro.remaining : Pomodoro.minutes * 60)
    readonly property string endsText: Pomodoro.running
        ? "ends " + Qt.formatTime(new Date(Pomodoro.endMs), "HH:mm")
        : Pomodoro.paused ? "paused" : Pomodoro.done ? "finished" : "not started"
    readonly property var tasks: Todo.upcoming
    readonly property string nextText: tasks.length > 0 ? "Next: " + tasks[0].title : "Nothing left today"

    function fmt(secs) {
        const m = Math.floor(secs / 60)
        const s = secs % 60
        return String(m).padStart(2, "0") + ":" + String(s).padStart(2, "0")
    }

    // ── Open / close ───────────────────────────────────────────────────────
    readonly property bool canTake: PillState.owner === "" && !Overview.open && !DrawerState.open

    function goTo(g, e) {
        growAnim.stop()
        expandAnim.stop()
        growAnim.to = g
        expandAnim.to = e
        growAnim.start()
        expandAnim.start()
    }

    function show(next) {
        PillState.owner = "focus"
        visible = true
        stage = next
        goTo(1, next === "open" ? 1 : 0)
    }

    function close() {
        if (stage === "")
            return
        stage = ""
        armed = false
        FocusNotchState.openRequested = false
        goTo(0, 0)
    }

    NumberAnimation {
        id: growAnim
        target: root
        property: "grow"
        duration: 260
        easing.type: Easing.InOutCubic
        onFinished: {
            if (root.stage === "" && root.grow < 0.01) {
                root.visible = false
                if (PillState.owner === "focus")
                    PillState.owner = ""
            }
        }
    }

    NumberAnimation {
        id: expandAnim
        target: root
        property: "expand"
        duration: 320
        easing.type: Easing.InOutCubic
    }

    // the pointer has to rest on the pill a moment, so passing over it on the
    // way to the screen edge does not open it
    Timer {
        id: enterTimer
        interval: 180
        onTriggered: {
            if (FocusNotchState.pillHovered && root.armed && root.canTake)
                root.show("hover")
        }
    }

    // the strip closes shortly after the pointer leaves it
    Timer {
        id: leaveTimer
        interval: 300
        onTriggered: {
            if (root.stage === "hover" && !cardHover.hovered)
                root.close()
        }
    }

    Connections {
        target: FocusNotchState
        function onPillHoveredChanged() {
            if (FocusNotchState.pillHovered) {
                enterTimer.restart()
            } else {
                root.armed = true
                enterTimer.stop()
            }
        }
        function onOpenRequestedChanged() {
            if (FocusNotchState.openRequested) {
                if (root.stage !== "open" && (root.canTake || root.stage === "hover"))
                    root.show("open")
            } else if (root.stage !== "") {
                root.close()
            }
        }
    }

    // another panel took the pill, so this one gives way
    Connections {
        target: PillState
        function onOwnerChanged() {
            if (PillState.owner !== "focus" && root.stage !== "") {
                root.close()
            }
        }
    }

    // a click in the band outside the card closes the open panel
    MouseArea {
        id: catcher
        anchors.fill: parent
        onClicked: root.close()
    }

    Notch {
        bodyWidth: card.width
        bodyHeight: card.height
        x: card.x - bodyX
        y: card.y
    }

    // small round progress ring with the minutes in the middle
    component Ring: Item {
        id: ring

        property real fraction: 0
        property string label: ""
        property color tint: Theme.accent
        property int size: 48

        implicitWidth: size
        implicitHeight: size

        onFractionChanged: canvas.requestPaint()
        onTintChanged: canvas.requestPaint()

        Canvas {
            id: canvas
            anchors.fill: parent
            onPaint: {
                const ctx = getContext("2d")
                const c = width / 2
                const r = c - 2.5
                ctx.reset()
                ctx.lineWidth = 3
                ctx.lineCap = "round"

                ctx.strokeStyle = String(Qt.alpha(Theme.fg, 0.15))
                ctx.beginPath()
                ctx.arc(c, c, r, 0, 2 * Math.PI)
                ctx.stroke()

                if (ring.fraction > 0) {
                    ctx.strokeStyle = String(ring.tint)
                    ctx.beginPath()
                    ctx.arc(c, c, r, -Math.PI / 2, -Math.PI / 2 + 2 * Math.PI * ring.fraction)
                    ctx.stroke()
                }
            }
        }

        Text {
            anchors.centerIn: parent
            text: ring.label
            color: Theme.fg
            font.family: Theme.fontFamilyAlt
            font.pixelSize: Math.round(ring.size * 0.34)
            font.bold: true
        }
    }

    // a pill button: accent when it is the main action, grey otherwise
    component PillButton: Rectangle {
        id: btn

        property string label
        property bool main: false
        signal clicked()

        implicitWidth: caption.implicitWidth + 24
        implicitHeight: 28
        radius: height / 2
        color: main ? (mouse.containsMouse ? Qt.lighter(Theme.accent, 1.1) : Theme.accent)
                    : (mouse.containsMouse ? Qt.alpha(Theme.fg, 0.2) : Qt.alpha(Theme.fg, 0.1))
        Behavior on color { ColorAnimation { duration: 120 } }

        Text {
            id: caption
            anchors.centerIn: parent
            text: btn.label
            color: btn.main ? Theme.bg : Theme.fg
            font.family: Theme.fontFamily
            font.pixelSize: 11
            font.bold: true
        }
        MouseArea {
            id: mouse
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: btn.clicked()
        }
    }

    Rectangle {
        id: card

        readonly property real stripW: PillState.pillWidth + (root.hoverW - PillState.pillWidth) * root.grow
        readonly property real stripH: PillState.pillHeight + (root.hoverH - PillState.pillHeight) * root.grow

        width: stripW + (root.openW - stripW) * root.expand
        height: stripH + (root.openH - stripH) * root.expand
        x: (root.width - width) / 2
        y: PillState.pillTop
        color: "transparent"
        clip: true

        HoverHandler {
            id: cardHover
            onHoveredChanged: {
                if (hovered)
                    leaveTimer.stop()
                else if (root.stage === "hover")
                    leaveTimer.restart()
            }
        }

        // a click on the strip opens the panel; one on the open panel stays on it
        MouseArea {
            anchors.fill: parent
            onClicked: if (root.stage === "hover") root.show("open")
        }

        Item {
            id: keyHost
            anchors.fill: parent
            focus: true
            Keys.onEscapePressed: root.close()
        }

        // ── The strip ──────────────────────────────────────────────────────
        Item {
            id: strip
            width: root.hoverW
            height: root.hoverH
            x: (card.width - width) / 2
            opacity: Math.max(0, (root.grow - 0.5) * 2) * Math.max(0, 1 - root.expand * 2)
            visible: opacity > 0

            Row {
                anchors.fill: parent
                anchors.leftMargin: 18
                anchors.rightMargin: 18
                spacing: 14

                Ring {
                    anchors.verticalCenter: parent.verticalCenter
                    fraction: root.ringFraction
                    label: root.ringMinutes
                    tint: Pomodoro.done ? Theme.red : Pomodoro.paused ? Theme.disabled : Theme.accent
                }

                Column {
                    anchors.verticalCenter: parent.verticalCenter
                    width: strip.width - 36 - 48 - 14 - 14 - buttons.width
                    spacing: 4

                    Text {
                        text: root.phaseLabel
                        color: Qt.alpha(Theme.fg, 0.5)
                        font.family: Theme.fontFamilyAlt
                        font.pixelSize: 10
                        font.letterSpacing: 1
                    }
                    Text {
                        width: parent.width
                        text: root.readout + "  ·  " + root.endsText
                        color: Theme.fg
                        font.family: Theme.fontFamilyAlt
                        font.pixelSize: 14
                        font.bold: true
                        elide: Text.ElideRight
                    }
                    Rectangle {
                        width: parent.width
                        height: 3
                        radius: 1.5
                        color: Qt.alpha(Theme.fg, 0.12)

                        Rectangle {
                            width: parent.width * root.ringFraction
                            height: parent.height
                            radius: parent.radius
                            color: Pomodoro.done ? Theme.red : Pomodoro.paused ? Theme.disabled : Theme.accent
                        }
                    }
                    Text {
                        width: parent.width
                        text: root.nextText
                        color: Qt.alpha(Theme.fg, 0.5)
                        font.family: Theme.fontFamily
                        font.pixelSize: 11
                        elide: Text.ElideRight
                    }
                }

                Row {
                    id: buttons
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 8

                    PillButton {
                        label: Pomodoro.running ? "PAUSE" : Pomodoro.paused ? "RESUME" : "START"
                        main: true
                        onClicked: Pomodoro.toggle()
                    }
                    PillButton {
                        visible: Pomodoro.active || Pomodoro.done
                        label: "STOP"
                        onClicked: Pomodoro.stop()
                    }
                }
            }
        }

        // ── The open panel ─────────────────────────────────────────────────
        Item {
            id: panel
            width: root.openW
            height: root.openH
            x: (card.width - width) / 2
            opacity: Math.max(0, (root.expand - 0.5) * 2)
            visible: opacity > 0

            // header: the day, and the control drawer
            Item {
                x: 18
                y: 8
                width: parent.width - 36
                height: 30

                Row {
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 10

                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        text: "TODAY"
                        color: Qt.alpha(Theme.fg, 0.5)
                        font.family: Theme.fontFamilyAlt
                        font.pixelSize: 10
                        font.letterSpacing: 1
                    }
                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        text: Qt.formatDate(Todo.toDate(Todo.today), "dddd d MMMM")
                        color: Theme.fg
                        font.family: Theme.fontFamily
                        font.pixelSize: 13
                        font.bold: true
                    }
                }

                // nf-md-tune: opens the control drawer
                Text {
                    id: tune
                    anchors.verticalCenter: parent.verticalCenter
                    anchors.right: parent.right
                    text: "󰘮"
                    color: tuneMouse.containsMouse ? Theme.accent : Qt.alpha(Theme.fg, 0.7)
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.iconSize
                    Behavior on color { ColorAnimation { duration: 120 } }

                    MouseArea {
                        id: tuneMouse
                        anchors.fill: parent
                        anchors.margins: -6
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: DrawerState.show()
                    }
                }
            }

            // the pomodoro card
            Rectangle {
                id: focusCard
                x: 12
                y: 46
                width: 190
                height: panel.height - y - 12
                radius: 12
                color: Qt.alpha(Theme.fg, 0.06)

                Column {
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.top: parent.top
                    anchors.margins: 14
                    spacing: 8

                    Ring {
                        fraction: root.ringFraction
                        label: root.ringMinutes
                        size: 56
                        tint: Pomodoro.done ? Theme.red : Pomodoro.paused ? Theme.disabled : Theme.accent
                    }
                    Text {
                        text: root.phaseLabel
                        color: Qt.alpha(Theme.fg, 0.5)
                        font.family: Theme.fontFamilyAlt
                        font.pixelSize: 10
                        font.letterSpacing: 1
                    }
                    Text {
                        text: root.readout
                        color: Pomodoro.done ? Theme.red : Theme.fg
                        font.family: Theme.fontFamilyAlt
                        font.pixelSize: 24
                        font.bold: true
                    }
                    Text {
                        text: root.endsText
                        color: Qt.alpha(Theme.fg, 0.5)
                        font.family: Theme.fontFamily
                        font.pixelSize: 11
                    }
                    // the cycle: four dots, filled as work sessions finish
                    Row {
                        spacing: 6
                        Repeater {
                            model: 4
                            Rectangle {
                                required property int index
                                width: 7
                                height: 7
                                radius: 3.5
                                color: index < root.setFilled ? Theme.accent : Qt.alpha(Theme.fg, 0.15)
                            }
                        }
                    }
                }

                Row {
                    anchors.left: parent.left
                    anchors.bottom: parent.bottom
                    anchors.margins: 12
                    spacing: 8

                    PillButton {
                        label: Pomodoro.running ? "PAUSE" : Pomodoro.paused ? "RESUME" : "START"
                        main: true
                        onClicked: Pomodoro.toggle()
                    }
                    PillButton {
                        visible: Pomodoro.active || Pomodoro.done
                        label: "STOP"
                        onClicked: Pomodoro.stop()
                    }
                }
            }

            // what is left to do today
            Item {
                id: list
                x: focusCard.x + focusCard.width + 16
                y: 46
                width: panel.width - x - 18
                height: panel.height - y - 12

                Item {
                    id: listHead
                    width: parent.width
                    height: 20

                    Text {
                        text: "NEXT"
                        color: Qt.alpha(Theme.fg, 0.5)
                        font.family: Theme.fontFamilyAlt
                        font.pixelSize: 10
                        font.letterSpacing: 1
                    }
                    Text {
                        anchors.right: parent.right
                        text: root.tasks.length + " left"
                        color: Qt.alpha(Theme.fg, 0.5)
                        font.family: Theme.fontFamily
                        font.pixelSize: 11
                    }
                }

                Column {
                    y: listHead.height + 4
                    width: parent.width

                    Repeater {
                        model: root.tasks.slice(0, root.maxRows)

                        Item {
                            id: row
                            required property var modelData

                            readonly property bool late: modelData.due < Todo.today
                            readonly property color tint: late || modelData.priority === 1 ? Theme.red
                                : modelData.priority === 2 ? Theme.accent
                                : modelData.priority === 3 ? Theme.secondary
                                : Qt.alpha(Theme.fg, 0.5)

                            width: parent.width
                            height: 34

                            // the circle ticks the task
                            Rectangle {
                                id: box
                                anchors.verticalCenter: parent.verticalCenter
                                width: 16
                                height: 16
                                radius: 8
                                color: boxMouse.containsMouse ? Qt.alpha(row.tint, 0.3) : "transparent"
                                border.width: 2
                                border.color: row.tint

                                MouseArea {
                                    id: boxMouse
                                    anchors.fill: parent
                                    anchors.margins: -6
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: Todo.toggle(row.modelData)
                                }
                            }
                            Text {
                                anchors.verticalCenter: parent.verticalCenter
                                anchors.left: box.right
                                anchors.leftMargin: 12
                                anchors.right: tag.left
                                anchors.rightMargin: 10
                                text: row.modelData.title
                                color: Theme.fg
                                font.family: Theme.fontFamily
                                font.pixelSize: 12
                                elide: Text.ElideRight
                            }
                            Text {
                                id: tag
                                anchors.verticalCenter: parent.verticalCenter
                                anchors.right: parent.right
                                text: row.late ? "overdue" : row.modelData.priority > 0 ? "p" + row.modelData.priority : ""
                                color: row.late ? Theme.red : Qt.alpha(Theme.fg, 0.5)
                                font.family: Theme.fontFamily
                                font.pixelSize: 11
                            }
                        }
                    }
                }

                Text {
                    visible: root.tasks.length === 0
                    y: listHead.height + 12
                    text: "Nothing left today"
                    color: Qt.alpha(Theme.fg, 0.5)
                    font.family: Theme.fontFamily
                    font.pixelSize: 12
                }

                Text {
                    visible: root.tasks.length > root.maxRows
                    anchors.bottom: parent.bottom
                    text: "+" + (root.tasks.length - root.maxRows) + " more"
                    color: Qt.alpha(Theme.fg, 0.5)
                    font.family: Theme.fontFamily
                    font.pixelSize: 11
                }
            }
        }
    }
}
