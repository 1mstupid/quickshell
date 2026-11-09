import QtQuick
import Quickshell
import Quickshell.Wayland
import "../../services"
import "../../services/menu"
import "../notch"

// The focus notch: the bar's center pill grows into the task timer and, on a
// click, into today's tasks. Hover the pill and it widens into a strip with the
// task in focus, the time spent on it so far, and pause and done. With nothing
// in focus it offers the next task instead. Click the strip (or run
// `qs ipc call focusnotch toggle`) and it opens further: the timer card on the
// left, what is left to do from todo.md on the right, with the hour each is due.
// Clicking a task there puts it in focus (it does not tick it); the check that
// shows on a hovered row ticks it. The control icon opens the control drawer,
// since the strip hides the clock that used to do that. The strip closes when
// the pointer leaves it; the open panel closes on Escape or a click outside.
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
    readonly property int hoverW: 520
    readonly property int hoverH: 78
    readonly property int openW: 580
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
    readonly property var tasks: Todo.upcoming
    readonly property bool focusOn: TaskFocus.active
    // the first task that is not the one in focus
    readonly property var nextTask: {
        const t = tasks.find(x => !TaskFocus.sameTask(x))
        return t !== undefined ? t : null
    }
    readonly property int elapsedMin: Math.floor(TaskFocus.elapsedMs / 60000)
    // the ring goes round once an hour
    readonly property real ringFraction: focusOn ? (TaskFocus.elapsedMs % 3600000) / 3600000 : 0
    readonly property string ringLabel: !focusOn ? "" : elapsedMin < 60 ? String(elapsedMin) : Math.floor(elapsedMin / 60) + "h"
    readonly property color tint: TaskFocus.paused ? Theme.disabled : Theme.accent
    readonly property string stateLabel: !focusOn ? "NOTHING IN FOCUS" : TaskFocus.paused ? "PAUSED" : "FOCUS"
    readonly property string clockText: fmtClock(TaskFocus.elapsedMs)
    // time banked on the task before this run, plus this run
    readonly property int totalMin: Math.floor(((TaskFocus.item ? TaskFocus.item.spent * 60000 : 0) + TaskFocus.elapsedMs) / 60000)
    readonly property string totalText: fmtMin(totalMin)
    readonly property string nextText: nextTask !== null
        ? "Next: " + nextTask.title + (nextTask.time !== "" && nextTask.due === Todo.today ? "  " + nextTask.time : "")
        : "Nothing else today"

    function fmtClock(ms) {
        const secs = Math.floor(ms / 1000)
        const h = Math.floor(secs / 3600)
        const m = Math.floor(secs / 60) % 60
        const s = secs % 60
        const mm = String(m).padStart(2, "0")
        const ss = String(s).padStart(2, "0")
        return h > 0 ? h + ":" + mm + ":" + ss : mm + ":" + ss
    }

    function fmtMin(m) {
        const h = Math.floor(m / 60)
        return h > 0 ? h + "h" + String(m % 60).padStart(2, "0") + "m" : m + "m"
    }

    // the right-hand label of a task: the hour for today's, the date for overdue
    function whenText(task) {
        return task.due < Todo.today ? Qt.formatDate(Todo.toDate(task.due), "d MMM") : task.time
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
                    label: root.ringLabel
                    tint: root.tint
                }

                Column {
                    anchors.verticalCenter: parent.verticalCenter
                    width: strip.width - 36 - 48 - 14 - 14 - buttons.width
                    spacing: 4

                    Text {
                        text: root.stateLabel
                        color: Qt.alpha(Theme.fg, 0.5)
                        font.family: Theme.fontFamilyAlt
                        font.pixelSize: 10
                        font.letterSpacing: 1
                    }
                    Text {
                        width: parent.width
                        text: root.focusOn ? TaskFocus.title : root.nextTask !== null ? root.nextTask.title : "Nothing left today"
                        color: Theme.fg
                        font.family: Theme.fontFamily
                        font.pixelSize: 14
                        font.bold: true
                        elide: Text.ElideRight
                    }
                    Item {
                        width: parent.width
                        height: 14

                        Text {
                            id: spentLine
                            anchors.left: parent.left
                            text: root.focusOn ? root.clockText + "  ·  total " + root.totalText : ""
                            color: Qt.alpha(Theme.fg, 0.5)
                            font.family: Theme.fontFamilyAlt
                            font.pixelSize: 11
                        }
                        Text {
                            anchors.right: parent.right
                            anchors.left: root.focusOn ? spentLine.right : parent.left
                            anchors.leftMargin: root.focusOn ? 12 : 0
                            horizontalAlignment: root.focusOn ? Text.AlignRight : Text.AlignLeft
                            text: root.focusOn ? root.nextText : root.nextTask !== null ? root.whenText(root.nextTask) : ""
                            color: Qt.alpha(Theme.fg, 0.5)
                            font.family: Theme.fontFamily
                            font.pixelSize: 11
                            elide: Text.ElideRight
                        }
                    }
                }

                Row {
                    id: buttons
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 8

                    PillButton {
                        visible: root.focusOn
                        label: TaskFocus.running ? "PAUSE" : "RESUME"
                        onClicked: TaskFocus.toggle()
                    }
                    PillButton {
                        visible: root.focusOn
                        label: "DONE"
                        main: true
                        onClicked: TaskFocus.complete()
                    }
                    PillButton {
                        visible: !root.focusOn && root.nextTask !== null
                        label: "FOCUS"
                        main: true
                        onClicked: TaskFocus.focus(root.nextTask)
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
            }

            // the timer card
            Rectangle {
                id: focusCard
                x: 12
                y: 46
                width: 212
                height: panel.height - y - 12
                radius: 12
                color: Qt.alpha(Theme.fg, 0.06)

                Column {
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.top: parent.top
                    anchors.margins: 14
                    spacing: 10

                    Row {
                        spacing: 12

                        Ring {
                            fraction: root.ringFraction
                            label: root.ringLabel
                            size: 52
                            tint: root.tint
                        }
                        Column {
                            anchors.verticalCenter: parent.verticalCenter
                            spacing: 2

                            Text {
                                text: root.stateLabel
                                color: Qt.alpha(Theme.fg, 0.5)
                                font.family: Theme.fontFamilyAlt
                                font.pixelSize: 10
                                font.letterSpacing: 1
                            }
                            Text {
                                visible: root.focusOn
                                text: root.clockText
                                color: Theme.fg
                                font.family: Theme.fontFamilyAlt
                                font.pixelSize: 22
                                font.bold: true
                            }
                        }
                    }

                    Text {
                        width: parent.width
                        text: root.focusOn ? TaskFocus.title : "Pick a task from the list to start timing it."
                        color: root.focusOn ? Theme.fg : Qt.alpha(Theme.fg, 0.5)
                        font.family: Theme.fontFamily
                        font.pixelSize: 13
                        font.bold: root.focusOn
                        wrapMode: Text.WordWrap
                        maximumLineCount: 2
                        elide: Text.ElideRight
                    }
                    Text {
                        visible: root.focusOn
                        text: "total " + root.totalText + (TaskFocus.item && TaskFocus.item.time !== "" ? "  ·  due " + TaskFocus.item.time : "")
                        color: Qt.alpha(Theme.fg, 0.5)
                        font.family: Theme.fontFamily
                        font.pixelSize: 11
                    }
                }

                Row {
                    visible: root.focusOn
                    anchors.left: parent.left
                    anchors.bottom: parent.bottom
                    anchors.margins: 12
                    spacing: 8

                    PillButton {
                        label: TaskFocus.running ? "PAUSE" : "RESUME"
                        onClicked: TaskFocus.toggle()
                    }
                    PillButton {
                        label: "STOP"
                        onClicked: TaskFocus.stop()
                    }
                    PillButton {
                        label: "DONE"
                        main: true
                        onClicked: TaskFocus.complete()
                    }
                }
            }

            // what is left to do
            Item {
                id: todoList
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
                            readonly property bool inFocus: TaskFocus.sameTask(modelData)
                            readonly property color tint: late || modelData.priority === 1 ? Theme.red
                                : modelData.priority === 2 ? Theme.accent
                                : modelData.priority === 3 ? Theme.secondary
                                : Qt.alpha(Theme.fg, 0.5)

                            width: parent.width
                            height: 34

                            HoverHandler { id: rowHover }

                            Rectangle {
                                anchors.fill: parent
                                anchors.topMargin: 1
                                anchors.bottomMargin: 1
                                radius: 8
                                color: row.inFocus ? Qt.alpha(Theme.accent, 0.14)
                                     : rowHover.hovered ? Qt.alpha(Theme.fg, 0.06) : "transparent"
                                Behavior on color { ColorAnimation { duration: 120 } }
                            }

                            // a click puts the task in focus; it does not tick it
                            MouseArea {
                                anchors.fill: parent
                                cursorShape: Qt.PointingHandCursor
                                onClicked: TaskFocus.focus(row.modelData)
                            }

                            Rectangle {
                                id: box
                                anchors.verticalCenter: parent.verticalCenter
                                anchors.left: parent.left
                                anchors.leftMargin: 8
                                width: 16
                                height: 16
                                radius: 8
                                color: row.inFocus ? row.tint : "transparent"
                                border.width: 2
                                border.color: row.tint
                            }
                            Text {
                                anchors.verticalCenter: parent.verticalCenter
                                anchors.left: box.right
                                anchors.leftMargin: 12
                                anchors.right: whenLabel.left
                                anchors.rightMargin: 10
                                text: row.modelData.title
                                color: Theme.fg
                                font.family: Theme.fontFamily
                                font.pixelSize: 12
                                font.bold: row.inFocus
                                elide: Text.ElideRight
                            }
                            Text {
                                id: whenLabel
                                anchors.verticalCenter: parent.verticalCenter
                                anchors.right: tick.left
                                anchors.rightMargin: 6
                                text: root.whenText(row.modelData)
                                color: row.late ? Theme.red : Qt.alpha(Theme.fg, 0.5)
                                font.family: Theme.fontFamilyAlt
                                font.pixelSize: 11
                            }
                            // nf-md-check: ticks the task, shown on a hovered row
                            Text {
                                id: tick
                                anchors.verticalCenter: parent.verticalCenter
                                anchors.right: parent.right
                                anchors.rightMargin: 8
                                width: 16
                                horizontalAlignment: Text.AlignHCenter
                                text: "󰄬"
                                opacity: rowHover.hovered ? 1 : 0
                                color: tickMouse.containsMouse ? Theme.accent : Qt.alpha(Theme.fg, 0.7)
                                font.family: Theme.fontFamily
                                font.pixelSize: Theme.iconSize
                                Behavior on opacity { NumberAnimation { duration: 120 } }

                                MouseArea {
                                    id: tickMouse
                                    anchors.fill: parent
                                    anchors.margins: -5
                                    enabled: rowHover.hovered
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: Todo.toggle(row.modelData)
                                }
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
