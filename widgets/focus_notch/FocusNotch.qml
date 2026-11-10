import QtQuick
import Quickshell
import Quickshell.Wayland
import "../../services"
import "../../services/menu"
import "../notch"
import "../bar/media"

// The focus notch: the bar's center pill grows into the task timer and, on a
// click, into a panel with a row of page buttons along the top. Hover the pill
// and it widens into a strip with the task in focus, the time spent on it so
// far, and pause and done; with nothing in focus it offers the block the
// schedule has on now. Click the strip (or run `qs ipc call focusnotch toggle`)
// and it opens further:
//   Home   the now-playing card, and what is left to do: todo.md's tasks together
//          with today's blocks from schedule.md. A click puts a row in focus (it
//          does not tick it), the check on a hovered row ticks it, and the box at
//          the bottom adds a task to today, typed the way todo.md has it.
//   Week   the schedule's grid, with today and the block that is on now marked.
//   Focus  the timer large, and the time tracked today and this week.
// The strip closes when the pointer leaves it; the open panel closes on Escape
// or a click outside.
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
    readonly property int openH: 280

    // "" closed, "hover" the strip, "open" the full panel
    property string stage: ""
    // the open panel's page: "home", "week" or "focus", remembered across openings
    readonly property string tab: FocusNotchState.page
    readonly property var pages: ["home", "week", "focus"]
    readonly property int pageIndex: Math.max(0, pages.indexOf(tab))
    // wraps at both ends
    function stepPage(delta) {
        const n = pages.length
        FocusNotchState.setPage(pages[(pageIndex + delta + n) % n])
    }
    // after a close the pointer has to leave the pill before it can open the strip again
    property bool armed: true
    onStageChanged: if (stage === "open") keyHost.forceActiveFocus()
    // 0 = the bar pill, 1 = the strip; 0 = the strip, 1 = the full panel
    property real grow: 0
    property real expand: 0

    // ── Data ───────────────────────────────────────────────────────────────
    // what is left to do: overdue and today's tasks from todo.md, together with
    // the blocks of today's schedule that have no task yet (see Schedule)
    readonly property var rows: Schedule.agenda
    readonly property bool focusOn: TaskFocus.active
    // the row of the block that is on now, if it is still to do
    readonly property var nowRow: {
        const t = Schedule.currentTitle
        const r = t === "" ? undefined : rows.find(x => x.due === Todo.today && x.title === t)
        return r !== undefined ? r : null
    }
    // what the strip offers with nothing in focus: the block that is on now, else the first row
    readonly property var nextRow: {
        if (nowRow !== null && !TaskFocus.sameTask(nowRow))
            return nowRow
        const r = rows.find(x => !TaskFocus.sameTask(x))
        return r !== undefined ? r : null
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
    readonly property string nextText: nextRow !== null
        ? "Next: " + nextRow.title + (nextRow.time !== "" && !nextRow.late ? "  " + nextRow.time : "")
        : "Nothing else today"
    // the block the schedule has on now, with its subject and when it ends
    readonly property string nowText: {
        const c = Schedule.current
        if (c === null)
            return ""
        const what = c.planned && c.subject !== c.name ? c.name + " · " + c.subject : c.name
        return what + " until " + Schedule.fmt(c.end)
    }

    // The time tracked: tasks due today with time on them (and the one in focus,
    // live), against the minutes the schedule planned for them, and the total for
    // today and for this week, Sunday to Saturday like the usage dashboard. The
    // time sits on the day the task is due, so work on an overdue task counts there.
    readonly property var tracked: {
        const sunday = Todo.addDays(Todo.today, -Todo.toDate(Todo.today).getDay())
        const saturday = Todo.addDays(sunday, 6)
        const out = []
        let today = 0
        let week = 0
        for (const t of Todo.items) {
            const on = TaskFocus.sameTask(t)
            const spent = t.spent + (on ? elapsedMin : 0)
            if (t.due >= sunday && t.due <= saturday)
                week += spent
            if (t.due !== Todo.today)
                continue
            today += spent
            if (spent > 0 || on)
                out.push({ title: t.title, spent: spent, planned: Schedule.minutesFor(t.title),
                           done: t.done, focused: on })
        }
        out.sort((a, b) => b.spent - a.spent)
        return { rows: out, today: today, week: week }
    }

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

    // the right-hand label of a row: the hour for today's, the date for overdue
    function whenText(r) {
        return r.late ? Qt.formatDate(Todo.toDate(r.due), "d MMM") : r.time
    }

    // starts timing a row; a block of the schedule becomes a task first
    function focusRow(r) {
        if (r.kind === "slot")
            Todo.materialize(r, false)
        TaskFocus.focus(r)
    }

    // ticks a row; a block of the schedule is added to the file already ticked
    function tickRow(r) {
        if (r.kind === "slot")
            Todo.materialize(r, true)
        else
            Todo.toggle(r.task)
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

        // wheel over the strip steps the page; summed so a touchpad does not skip pages
        WheelHandler {
            enabled: root.stage === "hover"
            property real sum: 0
            onWheel: event => {
                sum += event.angleDelta.y
                if (Math.abs(sum) < 120)
                    return
                root.stepPage(sum < 0 ? 1 : -1)
                sum = 0
            }
        }

        Item {
            id: keyHost
            anchors.fill: parent
            focus: true
            Keys.onEscapePressed: root.close()
            Keys.onLeftPressed: root.stepPage(-1)
            Keys.onRightPressed: root.stepPage(1)
        }

        // which page the strip would open on: one dot per page, the current one long
        Row {
            visible: root.stage === "hover"
            anchors.horizontalCenter: card.horizontalCenter
            anchors.bottom: card.bottom
            anchors.bottomMargin: 5
            spacing: 5

            Repeater {
                model: root.pages

                Rectangle {
                    required property int index
                    width: index === root.pageIndex ? 12 : 4
                    height: 4
                    radius: 2
                    color: index === root.pageIndex ? Theme.accent : Qt.alpha(Theme.fg, 0.25)
                    Behavior on width { NumberAnimation { duration: 200; easing.type: Easing.OutCubic } }
                    Behavior on color { ColorAnimation { duration: 150 } }
                }
            }
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
                        text: root.focusOn ? TaskFocus.title : root.nextRow !== null ? root.nextRow.title : "Nothing left today"
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
                            text: root.focusOn ? root.nextText : root.nextRow !== null ? root.whenText(root.nextRow) : ""
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
                        visible: !root.focusOn && root.nextRow !== null
                        label: "FOCUS"
                        main: true
                        onClicked: root.focusRow(root.nextRow)
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

            // header: the Day | Week | Focus switch, and the date
            Item {
                x: 18
                y: 8
                width: parent.width - 36
                height: 30

                Row {
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 2

                    Repeater {
                        // icons, not names: the buttons sit in a row across the top of the panel
                        model: [{ key: "home", name: "󰋜" }, { key: "week", name: "󰃭" }, { key: "focus", name: "󰔛" }]

                        Rectangle {
                            id: tabButton
                            required property var modelData
                            readonly property bool on: root.tab === modelData.key

                            width: 40
                            height: 24
                            radius: 7
                            color: on ? Qt.alpha(Theme.fg, 0.12)
                                 : tabMouse.containsMouse ? Qt.alpha(Theme.fg, 0.06) : "transparent"
                            Behavior on color { ColorAnimation { duration: 120 } }

                            Text {
                                anchors.centerIn: parent
                                text: tabButton.modelData.name
                                color: tabButton.on ? Theme.fg : Qt.alpha(Theme.fg, 0.55)
                                font.family: Theme.fontFamily
                                font.pixelSize: 12
                                font.bold: tabButton.on
                            }
                            MouseArea {
                                id: tabMouse
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: {
                                    FocusNotchState.setPage(tabButton.modelData.key)
                                    keyHost.forceActiveFocus()
                                }
                            }
                        }
                    }
                }

                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    anchors.right: parent.right
                    text: Qt.formatDate(Todo.toDate(Todo.today), "dddd d MMMM")
                    color: Qt.alpha(Theme.fg, 0.7)
                    font.family: Theme.fontFamily
                    font.pixelSize: 12
                }
            }

            // ── Home: the now-playing card, and what is left to do ─────────
            Item {
                id: dayTab
                visible: root.tab === "home"
                y: 46
                width: panel.width
                height: panel.height - y

                // now playing: art, title and artist, and the transport
                Rectangle {
                    id: mediaCard
                    x: 12
                    width: 212
                    height: parent.height - 12
                    radius: 12
                    color: Qt.alpha(Theme.fg, 0.06)

                    // the same MPRIS state the bar's media wave reads
                    MediaState { id: media }

                    Column {
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.top: parent.top
                        anchors.margins: 14
                        spacing: 10

                        Rectangle {
                            width: parent.width
                            height: 130
                            radius: 10
                            color: Qt.alpha(Theme.fg, 0.08)
                            clip: true

                            Image {
                                anchors.fill: parent
                                source: media.player?.trackArtUrl ?? ""
                                fillMode: Image.PreserveAspectCrop
                                visible: status === Image.Ready
                            }
                            Text {
                                anchors.centerIn: parent
                                visible: !media.present
                                text: "󰝚"
                                color: Qt.alpha(Theme.fg, 0.3)
                                font.family: Theme.fontFamily
                                font.pixelSize: 30
                            }
                        }

                        Text {
                            width: parent.width
                            text: media.present ? (media.player?.trackTitle ?? "") : "Nothing playing"
                            color: media.present ? Theme.fg : Qt.alpha(Theme.fg, 0.5)
                            font.family: Theme.fontFamily
                            font.pixelSize: 13
                            font.bold: media.present
                            elide: Text.ElideRight
                        }
                        Text {
                            width: parent.width
                            visible: media.present
                            text: media.artistText
                            color: Qt.alpha(Theme.fg, 0.6)
                            font.family: Theme.fontFamily
                            font.pixelSize: 11
                            elide: Text.ElideRight
                        }
                    }

                    Row {
                        anchors.horizontalCenter: parent.horizontalCenter
                        anchors.bottom: parent.bottom
                        anchors.bottomMargin: 14
                        spacing: 18

                        Text {
                            readonly property bool allowed: media.player?.canGoPrevious ?? false
                            text: "󰒮"
                            color: !allowed ? Qt.alpha(Theme.fg, 0.25) : prevMa.containsMouse ? Theme.accent : Theme.fg
                            font.family: Theme.fontFamily
                            font.pixelSize: 20
                            MouseArea {
                                id: prevMa
                                anchors.fill: parent
                                anchors.margins: -8
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: if (parent.allowed) media.player.previous()
                            }
                        }
                        Text {
                            readonly property bool allowed: media.player?.canTogglePlaying ?? false
                            text: media.playing ? "󰏤" : "󰐊"
                            color: !allowed ? Qt.alpha(Theme.fg, 0.25) : playMa.containsMouse ? Theme.accent : Theme.fg
                            font.family: Theme.fontFamily
                            font.pixelSize: 20
                            MouseArea {
                                id: playMa
                                anchors.fill: parent
                                anchors.margins: -8
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: if (parent.allowed) media.player.togglePlaying()
                            }
                        }
                        Text {
                            readonly property bool allowed: media.player?.canGoNext ?? false
                            text: "󰒭"
                            color: !allowed ? Qt.alpha(Theme.fg, 0.25) : nextMa.containsMouse ? Theme.accent : Theme.fg
                            font.family: Theme.fontFamily
                            font.pixelSize: 20
                            MouseArea {
                                id: nextMa
                                anchors.fill: parent
                                anchors.margins: -8
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: if (parent.allowed) media.player.next()
                            }
                        }
                    }
                }

                // what is left to do: tasks and the schedule's blocks, scrolling when long
                Item {
                    id: todoList
                    x: focusCard.x + focusCard.width + 16
                    width: panel.width - x - 18
                    height: parent.height - 12

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
                            text: root.rows.length + " left"
                            color: Qt.alpha(Theme.fg, 0.5)
                            font.family: Theme.fontFamily
                            font.pixelSize: 11
                        }
                    }

                    ListView {
                        id: dayList
                        y: listHead.height + 4
                        width: parent.width
                        height: todoList.height - y - addRow.height - 6
                        clip: true
                        boundsBehavior: Flickable.StopAtBounds
                        model: root.rows

                        delegate: Item {
                            id: dayRowItem
                            required property var modelData

                            readonly property bool isSlot: modelData.kind === "slot"
                            readonly property bool inFocus: TaskFocus.sameTask(modelData)
                            readonly property bool isNow: modelData.due === Todo.today && modelData.title === Schedule.currentTitle
                            readonly property color tint: modelData.late || modelData.priority === 1 ? Theme.red
                                : modelData.priority === 2 ? Theme.accent
                                : modelData.priority === 3 ? Theme.secondary
                                : Qt.alpha(Theme.fg, isSlot ? 0.35 : 0.5)

                            width: dayList.width
                            height: 30

                            HoverHandler { id: rowHover }

                            Rectangle {
                                anchors.fill: parent
                                anchors.topMargin: 1
                                anchors.bottomMargin: 1
                                radius: 8
                                color: dayRowItem.inFocus ? Qt.alpha(Theme.accent, 0.14)
                                     : dayRowItem.isNow ? Qt.alpha(Theme.accent, 0.07)
                                     : rowHover.hovered ? Qt.alpha(Theme.fg, 0.06) : "transparent"
                                Behavior on color { ColorAnimation { duration: 120 } }
                            }

                            // a click puts it in focus; it does not tick it
                            MouseArea {
                                anchors.fill: parent
                                cursorShape: Qt.PointingHandCursor
                                onClicked: root.focusRow(dayRowItem.modelData)
                            }

                            Rectangle {
                                id: dot
                                anchors.verticalCenter: parent.verticalCenter
                                anchors.left: parent.left
                                anchors.leftMargin: 8
                                width: 16
                                height: 16
                                radius: 8
                                color: dayRowItem.inFocus ? dayRowItem.tint : "transparent"
                                border.width: dayRowItem.isSlot ? 1.5 : 2
                                border.color: dayRowItem.tint
                            }
                            Text {
                                anchors.verticalCenter: parent.verticalCenter
                                anchors.left: dot.right
                                anchors.leftMargin: 12
                                anchors.right: whenLabel.left
                                anchors.rightMargin: 10
                                text: dayRowItem.modelData.title
                                color: Theme.fg
                                font.family: Theme.fontFamily
                                font.pixelSize: 12
                                font.bold: dayRowItem.inFocus || dayRowItem.isNow
                                elide: Text.ElideRight
                            }
                            Text {
                                id: whenLabel
                                anchors.verticalCenter: parent.verticalCenter
                                anchors.right: tick.left
                                anchors.rightMargin: 6
                                text: root.whenText(dayRowItem.modelData)
                                color: dayRowItem.modelData.late ? Theme.red : Qt.alpha(Theme.fg, 0.5)
                                font.family: Theme.fontFamilyAlt
                                font.pixelSize: 11
                            }
                            // nf-md-check: ticks it, shown on a hovered row
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
                                    onClicked: root.tickRow(dayRowItem.modelData)
                                }
                            }
                        }
                    }

                    Text {
                        visible: root.rows.length === 0
                        y: listHead.height + 12
                        text: "Nothing left today"
                        color: Qt.alpha(Theme.fg, 0.5)
                        font.family: Theme.fontFamily
                        font.pixelSize: 12
                    }

                    // adds a task to today, typed in todo.md's own syntax: Call mom @16:30 p2
                    Rectangle {
                        id: addRow
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.bottom: parent.bottom
                        height: 32
                        radius: 8
                        color: input.activeFocus ? Qt.alpha(Theme.fg, 0.1) : Qt.alpha(Theme.fg, 0.05)
                        Behavior on color { ColorAnimation { duration: 120 } }

                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.IBeamCursor
                            onClicked: input.forceActiveFocus()
                        }

                        Text {
                            id: plus
                            anchors.verticalCenter: parent.verticalCenter
                            anchors.left: parent.left
                            anchors.leftMargin: 11
                            text: "+"
                            color: Qt.alpha(Theme.fg, 0.5)
                            font.family: Theme.fontFamilyAlt
                            font.pixelSize: 16
                        }
                        TextInput {
                            id: input
                            anchors.verticalCenter: parent.verticalCenter
                            anchors.left: plus.right
                            anchors.leftMargin: 10
                            anchors.right: parent.right
                            anchors.rightMargin: 10
                            clip: true
                            selectByMouse: true
                            color: Theme.fg
                            selectionColor: Theme.accent
                            selectedTextColor: Theme.bg
                            font.family: Theme.fontFamily
                            font.pixelSize: 12

                            onAccepted: {
                                if (Todo.addTask(text))
                                    text = ""
                            }
                            // Escape empties the box and gives the keys back; a second one closes the panel
                            Keys.onEscapePressed: {
                                text = ""
                                keyHost.forceActiveFocus()
                            }

                            Text {
                                visible: input.text === ""
                                text: "Add a task  ·  @16:30 p2"
                                color: Qt.alpha(Theme.fg, 0.35)
                                font: input.font
                            }
                        }
                    }
                }
            }

            // ── Week: the schedule's grid ──────────────────────────────────
            WeekGrid {
                visible: root.tab === "week"
                x: 12
                y: 46
                width: panel.width - 24
                height: panel.height - y - 10
            }

            // ── Focus: the task in focus, and the time tracked ─────────────
            Item {
                id: focusTab
                visible: root.tab === "focus"
                x: 18
                y: 46
                width: panel.width - 36
                height: panel.height - y - 12

                Item {
                    id: bigTimer
                    width: parent.width
                    height: 78

                    Ring {
                        id: bigRing
                        anchors.verticalCenter: parent.verticalCenter
                        size: 64
                        fraction: root.ringFraction
                        label: root.ringLabel
                        tint: root.tint
                    }
                    Column {
                        anchors.verticalCenter: parent.verticalCenter
                        anchors.left: bigRing.right
                        anchors.leftMargin: 16
                        anchors.right: bigButtons.left
                        anchors.rightMargin: 12
                        spacing: 3

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
                            font.pixelSize: 30
                            font.bold: true
                        }
                        Text {
                            width: parent.width
                            text: root.focusOn ? TaskFocus.title : root.nextRow !== null ? root.nextText : "Nothing left today"
                            color: root.focusOn ? Theme.fg : Qt.alpha(Theme.fg, 0.7)
                            font.family: Theme.fontFamily
                            font.pixelSize: 13
                            font.bold: root.focusOn
                            elide: Text.ElideRight
                        }
                    }
                    Row {
                        id: bigButtons
                        anchors.verticalCenter: parent.verticalCenter
                        anchors.right: parent.right
                        spacing: 8

                        PillButton {
                            visible: root.focusOn
                            label: TaskFocus.running ? "PAUSE" : "RESUME"
                            onClicked: TaskFocus.toggle()
                        }
                        PillButton {
                            visible: root.focusOn
                            label: "STOP"
                            onClicked: TaskFocus.stop()
                        }
                        PillButton {
                            visible: root.focusOn
                            label: "DONE"
                            main: true
                            onClicked: TaskFocus.complete()
                        }
                        PillButton {
                            visible: !root.focusOn && root.nextRow !== null
                            label: "FOCUS"
                            main: true
                            onClicked: root.focusRow(root.nextRow)
                        }
                    }
                }

                Item {
                    id: trackHead
                    y: bigTimer.height + 8
                    width: parent.width
                    height: 20

                    Text {
                        text: "TRACKED TODAY"
                        color: Qt.alpha(Theme.fg, 0.5)
                        font.family: Theme.fontFamilyAlt
                        font.pixelSize: 10
                        font.letterSpacing: 1
                    }
                    Text {
                        anchors.right: parent.right
                        text: "today " + root.fmtMin(root.tracked.today) + "  ·  week " + root.fmtMin(root.tracked.week)
                        color: Qt.alpha(Theme.fg, 0.5)
                        font.family: Theme.fontFamily
                        font.pixelSize: 11
                    }
                }

                ListView {
                    id: trackList
                    y: trackHead.y + trackHead.height + 2
                    width: parent.width
                    height: parent.height - y
                    clip: true
                    boundsBehavior: Flickable.StopAtBounds
                    model: root.tracked.rows

                    delegate: Item {
                        id: trackRow
                        required property var modelData
                        // against the block's planned time when it has one, else against the day's longest
                        readonly property real share: modelData.planned > 0
                            ? Math.min(1, modelData.spent / modelData.planned)
                            : (root.tracked.rows[0].spent > 0 ? modelData.spent / root.tracked.rows[0].spent : 0)

                        width: trackList.width
                        height: 26

                        Rectangle {
                            anchors.fill: parent
                            anchors.topMargin: 2
                            anchors.bottomMargin: 2
                            radius: 6
                            color: Qt.alpha(Theme.fg, 0.05)

                            Rectangle {
                                width: parent.width * trackRow.share
                                height: parent.height
                                radius: parent.radius
                                color: Qt.alpha(Theme.accent, trackRow.modelData.focused ? 0.35 : 0.22)
                            }
                        }
                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            anchors.left: parent.left
                            anchors.leftMargin: 10
                            anchors.right: spentLabel.left
                            anchors.rightMargin: 10
                            text: trackRow.modelData.title
                            color: trackRow.modelData.done ? Qt.alpha(Theme.fg, 0.6) : Theme.fg
                            font.family: Theme.fontFamily
                            font.pixelSize: 12
                            font.bold: trackRow.modelData.focused
                            elide: Text.ElideRight
                        }
                        Text {
                            id: spentLabel
                            anchors.verticalCenter: parent.verticalCenter
                            anchors.right: parent.right
                            anchors.rightMargin: 10
                            text: root.fmtMin(trackRow.modelData.spent)
                                + (trackRow.modelData.planned > 0 ? " / " + root.fmtMin(trackRow.modelData.planned) : "")
                            color: Qt.alpha(Theme.fg, 0.6)
                            font.family: Theme.fontFamilyAlt
                            font.pixelSize: 11
                        }
                    }
                }

                Text {
                    visible: root.tracked.rows.length === 0
                    y: trackHead.y + trackHead.height + 10
                    text: "Nothing tracked yet today"
                    color: Qt.alpha(Theme.fg, 0.5)
                    font.family: Theme.fontFamily
                    font.pixelSize: 12
                }
            }
        }
    }
}
