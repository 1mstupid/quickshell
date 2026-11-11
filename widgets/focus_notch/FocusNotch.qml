import QtQuick
import QtQuick.Effects
import Quickshell
import Quickshell.Wayland
import "../../services"
import "../../services/menu"
import "../notch"
import "../bar/media"

// The focus notch: the bar's center pill grows into the task timer and, on a
// click, into a panel with a row of page buttons along the top. Hover the pill
// and it widens into a strip with the task in focus, the time spent on it so
// far (or, for a block of the schedule, what is left of it and when it ends),
// and pause and done; with nothing in focus it offers the block the schedule
// has on now. Click the strip (or run `qs ipc call focusnotch toggle`)
// and it opens further. A header switches between Home and Work; Work holds the
// Day, Week and Focus pages, and a small switch on a row under the tabs picks between them:
//   Home   the now-playing card on the left, and the day on the right: the date,
//          what is on now and what comes next.
//   Day    what is left to do: todo.md's tasks together with today's blocks from
//          schedule.md. A click puts a row in focus (it does not tick it), the
//          check on a hovered row ticks it, and the box at the bottom adds a task
//          to today, typed the way todo.md has it.
//   Week   the schedule's grid, with today and the block that is on now marked.
//   Focus  the task in hand: its timer, pause, stop and done, and the time tracked today.
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
    readonly property int openH: 260

    // "" closed, "hover" the strip, "open" the full panel
    property string stage: ""
    // the open panel's page: "home", "day", "week" or "focus", remembered across openings
    readonly property string tab: FocusNotchState.page
    readonly property var pages: ["home", "day", "week", "focus"]
    readonly property int pageIndex: Math.max(0, pages.indexOf(tab))
    // Work is Day or Week; the Work tab returns to the one last shown
    property string lastWork: "day"
    onTabChanged: if (tab !== "home") lastWork = tab
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
    // what the strip and the focus card offer with nothing in focus
    readonly property var nextRow: {
        let best = null
        let bestGap = Infinity
        for (const r of rows) {
            if (TaskFocus.sameTask(r))
                continue
            const gap = r.late ? -1 : r.time === "" ? 100000 : Math.abs(minutesOf(r.time) - Schedule.nowMin)
            if (gap < bestGap) {
                bestGap = gap
                best = r
            }
        }
        return best
    }
    // the nearest open task after today, for the notice's second section
    readonly property var nextLater: {
        let best = null
        for (const t of Todo.items) {
            if (t.done || t.due === "" || t.due <= Todo.today)
                continue
            if (best === null || t.due < best.due
                    || (t.due === best.due && t.time !== "" && (best.time === "" || t.time < best.time)))
                best = t
        }
        return best
    }
    readonly property string laterText: {
        if (nextLater === null)
            return ""
        const day = nextLater.due === Todo.addDays(Todo.today, 1) ? "Tomorrow"
            : Qt.formatDate(Todo.toDate(nextLater.due), "ddd d MMM")
        return nextLater.time !== "" ? day + " · " + nextLater.time : day
    }
    function minutesOf(hhmm) {
        const p = hhmm.split(":")
        return parseInt(p[0]) * 60 + parseInt(p[1])
    }
    readonly property int elapsedMin: Math.floor(TaskFocus.elapsedMs / 60000)
    // the ring goes round once an hour
    readonly property real ringFraction: focusOn ? (TaskFocus.elapsedMs % 3600000) / 3600000 : 0
    readonly property string ringLabel: !focusOn ? "" : elapsedMin < 60 ? String(elapsedMin) : Math.floor(elapsedMin / 60) + "h"
    readonly property color tint: TaskFocus.paused ? Theme.disabled : Theme.accent
    readonly property string stripLabel: !focusOn ? "Nothing in focus" : TaskFocus.paused ? "Paused" : "Focus"
    readonly property string clockText: fmtClock(TaskFocus.elapsedMs)
    // time banked on the task before this run, plus this run
    readonly property double totalMs: (TaskFocus.item ? TaskFocus.item.spent * 60000 : 0) + TaskFocus.elapsedMs
    readonly property int totalMin: Math.floor(totalMs / 60000)
    readonly property string totalText: fmtMin(totalMin)
    // The minutes the schedule planned for the task in focus: 0 when it is not
    // a block of the schedule, and then the strip counts up instead of down.
    readonly property int plannedMin: focusOn ? Schedule.minutesFor(TaskFocus.title) : 0
    readonly property double leftMs: plannedMin * 60000 - totalMs
    readonly property real planFraction: plannedMin > 0 ? Math.min(1, totalMs / (plannedMin * 60000)) : 0
    // the strip's time line; the end time only means something while the clock runs
    readonly property string timeText: {
        if (!focusOn)
            return ""
        if (plannedMin <= 0)
            return clockText + "  ·  total " + totalText
        if (leftMs <= 0)
            return fmtMin(Math.ceil(-leftMs / 60000)) + " over"
        return fmtClock(leftMs) + " left" + (TaskFocus.running
            ? "  ·  ends " + Qt.formatTime(new Date(TaskFocus.now + leftMs), "HH:mm") : "")
    }
    readonly property string nextText: nextRow !== null
        ? "Next: " + nextRow.title + (nextRow.time !== "" && !nextRow.late ? "  " + nextRow.time : "")
        : "Nothing else today"
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
        // the bottom corners round off as the pill grows, so the panel reads as one soft shape
        corner: 12 + 8 * root.grow + 6 * root.expand
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

                    Row {
                        spacing: 6

                        Text {
                            text: root.stripLabel
                            color: Qt.alpha(Theme.fg, 0.55)
                            font.family: Theme.fontFamilySans
                            font.pixelSize: 11
                        }
                        // live dot: lit while the clock runs, grey while it is paused
                        Rectangle {
                            visible: root.focusOn
                            anchors.verticalCenter: parent.verticalCenter
                            width: 6
                            height: 6
                            radius: 3
                            color: TaskFocus.running ? Theme.green : Theme.disabled
                        }
                    }
                    Text {
                        width: parent.width
                        text: root.focusOn ? TaskFocus.title : root.nextRow !== null ? root.nextRow.title : "Nothing left today"
                        color: Theme.fg
                        font.family: Theme.fontFamilySans
                        font.pixelSize: 14
                        font.weight: Font.DemiBold
                        elide: Text.ElideRight
                    }
                    // progress through the planned time, only for a block of the schedule
                    Rectangle {
                        visible: root.plannedMin > 0
                        width: parent.width
                        height: 3
                        radius: 1.5
                        color: Qt.alpha(Theme.fg, 0.15)

                        Rectangle {
                            width: parent.width * root.planFraction
                            height: parent.height
                            radius: parent.radius
                            color: root.tint
                        }
                    }
                    Item {
                        width: parent.width
                        height: 14

                        Text {
                            id: spentLine
                            anchors.left: parent.left
                            text: root.timeText
                            color: Qt.alpha(Theme.fg, 0.5)
                            font.family: Theme.fontFamilyNum
                            font.pixelSize: 11
                        }
                        Text {
                            anchors.right: parent.right
                            anchors.left: root.focusOn ? spentLine.right : parent.left
                            anchors.leftMargin: root.focusOn ? 12 : 0
                            horizontalAlignment: root.focusOn ? Text.AlignRight : Text.AlignLeft
                            text: root.focusOn ? root.nextText : root.nextRow !== null ? root.whenText(root.nextRow) : ""
                            color: Qt.alpha(Theme.fg, 0.5)
                            font.family: root.focusOn ? Theme.fontFamilySans : Theme.fontFamilyNum
                            font.pixelSize: 11
                            elide: Text.ElideRight
                        }
                    }
                }

                Row {
                    id: buttons
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 8

                    IconButton {
                        visible: root.focusOn
                        glyph: TaskFocus.running ? "󰏤" : "󰐊"
                        onClicked: TaskFocus.toggle()
                    }
                    IconButton {
                        visible: root.focusOn
                        glyph: "󰄬"
                        main: true
                        onClicked: TaskFocus.complete()
                    }
                    IconButton {
                        visible: !root.focusOn && root.nextRow !== null
                        glyph: "󰐊"
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

            // header: the Home and Work tabs and, on Work, the Day | Week switch. The
            // tab that is on grows into a pill with its name; the other stays an icon.
            Item {
                x: 18
                y: 8
                width: parent.width - 36
                height: 30

                Row {
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 2

                    Repeater {
                        model: [{ key: "home", glyph: "󰋜", name: "Home" },
                                { key: "work", glyph: "󰸗", name: "Work" }]

                        Rectangle {
                            id: tabButton
                            required property var modelData
                            // Work is on for both of its pages
                            readonly property bool on: modelData.key === "home"
                                ? root.tab === "home" : root.tab !== "home"

                            // a square slot for the icon, then the name while the tab is on
                            width: on ? 32 + tabName.implicitWidth + 12 : 32
                            height: 24
                            radius: height / 2
                            clip: true
                            color: on ? Qt.alpha(Theme.fg, 0.12)
                                 : tabMouse.containsMouse ? Qt.alpha(Theme.fg, 0.06) : "transparent"
                            Behavior on width { NumberAnimation { duration: 200; easing.type: Easing.OutCubic } }
                            Behavior on color { ColorAnimation { duration: 120 } }

                            Text {
                                width: 32
                                height: parent.height
                                horizontalAlignment: Text.AlignHCenter
                                verticalAlignment: Text.AlignVCenter
                                text: tabButton.modelData.glyph
                                color: tabButton.on ? Theme.fg : Qt.alpha(Theme.fg, 0.55)
                                font.family: Theme.fontFamily
                                font.pixelSize: 12
                            }
                            Text {
                                id: tabName
                                x: 32
                                height: parent.height
                                verticalAlignment: Text.AlignVCenter
                                text: tabButton.modelData.name
                                opacity: tabButton.on ? 1 : 0
                                color: Theme.fg
                                font.family: Theme.fontFamilySans
                                font.pixelSize: 12
                                font.weight: Font.DemiBold
                                Behavior on opacity { NumberAnimation { duration: 150 } }
                            }
                            MouseArea {
                                id: tabMouse
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: {
                                    FocusNotchState.setPage(tabButton.modelData.key === "home" ? "home" : root.lastWork)
                                    keyHost.forceActiveFocus()
                                }
                            }
                        }
                    }
                }
            }

            // the two pages of Work, shown only there
            Rectangle {
                id: workSwitch
                x: 18
                y: 40
                width: segments.implicitWidth + 4
                height: 24
                radius: 7
                color: Qt.alpha(Theme.fg, 0.08)
                opacity: root.tab !== "home" ? 1 : 0
                visible: opacity > 0
                Behavior on opacity { NumberAnimation { duration: 150 } }

                Row {
                    id: segments
                    x: 2
                    y: 2
                    spacing: 2

                    Repeater {
                        model: [{ key: "day", name: "Day" }, { key: "week", name: "Week" }, { key: "focus", name: "Focus" }]

                        Rectangle {
                            id: segment
                            required property var modelData
                            readonly property bool on: root.tab === modelData.key

                            width: segName.implicitWidth + 20
                            height: 20
                            radius: 5
                            color: on ? Qt.alpha(Theme.fg, 0.14)
                                 : segMouse.containsMouse ? Qt.alpha(Theme.fg, 0.06) : "transparent"
                            Behavior on color { ColorAnimation { duration: 120 } }

                            Text {
                                id: segName
                                anchors.centerIn: parent
                                text: segment.modelData.name
                                color: segment.on ? Theme.fg : Qt.alpha(Theme.fg, 0.6)
                                font.family: Theme.fontFamilySans
                                font.pixelSize: 11
                            }
                            MouseArea {
                                id: segMouse
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: {
                                    FocusNotchState.setPage(segment.modelData.key)
                                    keyHost.forceActiveFocus()
                                }
                            }
                        }
                    }
                }
            }

            // ── Home: now playing ──────────────────────────────────────────
            Item {
                id: homeTab
                visible: root.tab === "home"
                y: 46
                width: panel.width
                height: panel.height - y

                // now playing, laid out like the reference: art and title on top, the
                // progress under them, the transport centred at the bottom
                Item {
                    id: mediaCard
                    x: 12
                    width: panel.width - 36 - 200
                    height: parent.height - 12

                    // the same MPRIS state the bar's media wave reads
                    MediaState { id: media }

                    Row {
                        id: mediaTop
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.top: parent.top
                        anchors.margins: 14
                        spacing: 14

                        Rectangle {
                            id: art
                            width: 64
                            height: 64
                            radius: 10
                            color: Qt.alpha(Theme.fg, 0.08)

                            // rounding by mask, since clip only cuts square corners
                            Item {
                                id: artMask
                                anchors.fill: parent
                                visible: false
                                layer.enabled: true
                                Rectangle { anchors.fill: parent; radius: art.radius; color: "white" }
                            }
                            Image {
                                anchors.fill: parent
                                source: media.player?.trackArtUrl ?? ""
                                fillMode: Image.PreserveAspectCrop
                                visible: status === Image.Ready
                                layer.enabled: true
                                layer.effect: MultiEffect {
                                    maskEnabled: true
                                    maskSource: artMask
                                }
                            }
                            Text {
                                anchors.centerIn: parent
                                visible: !media.present
                                text: "󰝚"
                                color: Qt.alpha(Theme.fg, 0.3)
                                font.family: Theme.fontFamily
                                font.pixelSize: 24
                            }
                        }

                        Column {
                            // leaves room on the right for the bars
                            width: mediaTop.width - 64 - mediaTop.spacing - 24
                            anchors.verticalCenter: parent.verticalCenter
                            spacing: 4

                            Text {
                                width: parent.width
                                text: media.present ? (media.player?.trackTitle ?? "") : "Nothing playing"
                                color: media.present ? Theme.fg : Qt.alpha(Theme.fg, 0.5)
                                font.family: Theme.fontFamilySans
                                font.pixelSize: 15
                                font.weight: media.present ? Font.DemiBold : Font.Normal
                                elide: Text.ElideRight
                            }
                            Text {
                                width: parent.width
                                visible: media.present
                                text: media.artistText
                                color: Qt.alpha(Theme.fg, 0.6)
                                font.family: Theme.fontFamilySans
                                font.pixelSize: 12
                                elide: Text.ElideRight
                            }
                        }
                    }

                    EqBars {
                        anchors.right: mediaTop.right
                        anchors.verticalCenter: mediaTop.verticalCenter
                        visible: media.present
                        playing: media.playing
                    }

                    // elapsed, a thin track, and the time left
                    Item {
                        id: progress
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.top: mediaTop.bottom
                        anchors.leftMargin: 14
                        anchors.rightMargin: 14
                        anchors.topMargin: 18
                        height: 14

                        Text {
                            id: elapsed
                            anchors.left: parent.left
                            anchors.verticalCenter: parent.verticalCenter
                            text: media.present ? media.fmt(media.pos) : ""
                            color: Qt.alpha(Theme.fg, 0.6)
                            font.family: Theme.fontFamilyNum
                            font.pixelSize: 11
                        }
                        Text {
                            id: remaining
                            anchors.right: parent.right
                            anchors.verticalCenter: parent.verticalCenter
                            visible: media.timed
                            text: media.timed ? "-" + media.fmt(media.len - media.pos) : ""
                            color: Qt.alpha(Theme.fg, 0.6)
                            font.family: Theme.fontFamilyNum
                            font.pixelSize: 11
                        }
                        Rectangle {
                            anchors.left: elapsed.right
                            anchors.right: remaining.left
                            anchors.leftMargin: 10
                            anchors.rightMargin: 10
                            anchors.verticalCenter: parent.verticalCenter
                            height: 4
                            radius: 2
                            color: Qt.alpha(Theme.fg, 0.15)

                            Rectangle {
                                anchors.left: parent.left
                                anchors.top: parent.top
                                anchors.bottom: parent.bottom
                                radius: parent.radius
                                color: Theme.fg
                                width: parent.width * (media.timed ? Math.min(1, media.pos / media.len) : 0)
                            }
                        }
                    }

                    // previous, play or pause, next: fixed cells, so the three share one centre line
                    Row {
                        anchors.horizontalCenter: parent.horizontalCenter
                        anchors.top: progress.bottom
                        anchors.topMargin: 12
                        spacing: 10

                        component Transport: Item {
                            id: cell
                            property string glyph: ""
                            property bool allowed: true
                            property int glyphSize: 24
                            signal tapped()

                            width: 40
                            height: 40

                            Text {
                                anchors.centerIn: parent
                                text: cell.glyph
                                color: !cell.allowed ? Qt.alpha(Theme.fg, 0.25)
                                     : ma.containsMouse ? Theme.accent : Theme.fg
                                font.family: Theme.fontFamily
                                font.pixelSize: cell.glyphSize
                            }
                            MouseArea {
                                id: ma
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: if (cell.allowed) cell.tapped()
                            }
                        }

                        Transport {
                            glyph: "󰑟"
                            allowed: media.player?.canGoPrevious ?? false
                            onTapped: media.player.previous()
                        }
                        Transport {
                            glyph: media.playing ? "󰏤" : "󰐊"
                            glyphSize: 32
                            allowed: media.player?.canTogglePlaying ?? false
                            onTapped: media.player.togglePlaying()
                        }
                        Transport {
                            glyph: "󰈑"
                            allowed: media.player?.canGoNext ?? false
                            onTapped: media.player.next()
                        }
                    }
                }

                // a thin line between the player and the day, as in the reference
                Rectangle {
                    x: mediaCard.x + mediaCard.width + 6
                    y: 6
                    width: 1
                    height: parent.height - 24
                    color: Qt.alpha(Theme.fg, 0.1)
                }

                // the day: the date, what is on now (or nearest) and the next task after today
                Column {
                    id: dayColumn
                    x: mediaCard.x + mediaCard.width + 18
                    width: 194
                    spacing: 8

                    // the date, top left: the weekday small in red, the date large, and a
                    // button that jumps to the Day page with the add box ready
                    Item {
                        width: parent.width
                        height: dateText.height

                        Column {
                            id: dateText

                            Text {
                                text: Qt.formatDate(Todo.toDate(Todo.today), "dddd").toUpperCase()
                                color: Theme.red
                                font.family: Theme.fontFamilySans
                                font.pixelSize: 10
                                font.weight: Font.DemiBold
                                font.letterSpacing: 1
                            }
                            Text {
                                text: Qt.formatDate(Todo.toDate(Todo.today), "d MMM")
                                color: Theme.fg
                                font.family: Theme.fontFamilySans
                                font.pixelSize: 22
                                font.weight: Font.DemiBold
                            }
                        }
                        Rectangle {
                            anchors.right: parent.right
                            anchors.top: parent.top
                            width: 26
                            height: 26
                            radius: 8
                            color: plusMouse.containsMouse ? Qt.alpha(Theme.fg, 0.2) : Qt.alpha(Theme.fg, 0.1)
                            Behavior on color { ColorAnimation { duration: 120 } }

                            Text {
                                anchors.centerIn: parent
                                text: "󰐕"
                                color: Theme.fg
                                font.family: Theme.fontFamily
                                font.pixelSize: 12
                            }
                            MouseArea {
                                id: plusMouse
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: {
                                    FocusNotchState.setPage("day")
                                    // the Day page is not visible yet, so focus waits a tick
                                    Qt.callLater(() => input.forceActiveFocus())
                                }
                            }
                        }
                    }

                    // today: what is nearest, with a button that puts it in focus
                    Rectangle {
                        width: parent.width
                        height: 50
                        radius: 10
                        color: Qt.alpha(Theme.fg, 0.06)

                        Row {
                            anchors.fill: parent
                            anchors.margins: 10
                            spacing: 10

                            Rectangle {
                                id: dayTile
                                anchors.verticalCenter: parent.verticalCenter
                                width: 30
                                height: 30
                                radius: 8
                                color: Qt.alpha(Theme.accent, 0.18)

                                Text {
                                    anchors.centerIn: parent
                                    text: "󰃭"
                                    color: Theme.accent
                                    font.family: Theme.fontFamily
                                    font.pixelSize: 14
                                }
                            }
                            Column {
                                anchors.verticalCenter: parent.verticalCenter
                                width: parent.width - dayTile.width - parent.spacing
                                       - (todayFocus.visible ? todayFocus.width + parent.spacing : 0)
                                spacing: 1

                                Text {
                                    width: parent.width
                                    text: root.nextRow !== null ? root.nextRow.title : "You're clear for today"
                                    color: Theme.fg
                                    font.family: Theme.fontFamilySans
                                    font.pixelSize: 12
                                    font.weight: Font.DemiBold
                                    elide: Text.ElideRight
                                }
                                Text {
                                    width: parent.width
                                    text: root.nextRow !== null ? root.whenText(root.nextRow) : "Enjoy your free time"
                                    color: Qt.alpha(Theme.fg, 0.6)
                                    font.family: root.nextRow !== null ? Theme.fontFamilyNum : Theme.fontFamilySans
                                    font.pixelSize: 10
                                    elide: Text.ElideRight
                                }
                            }
                            IconButton {
                                id: todayFocus
                                anchors.verticalCenter: parent.verticalCenter
                                width: 28
                                height: 28
                                visible: !root.focusOn && root.nextRow !== null
                                glyph: "󰐊"
                                main: true
                                onClicked: root.focusRow(root.nextRow)
                            }
                        }
                    }

                    // the next task after today
                    Text {
                        visible: root.nextLater !== null
                        text: "Next event"
                        color: Qt.alpha(Theme.fg, 0.5)
                        font.family: Theme.fontFamilySans
                        font.pixelSize: 10
                    }
                    Rectangle {
                        visible: root.nextLater !== null
                        width: parent.width
                        height: 46
                        radius: 10
                        color: Qt.alpha(Theme.fg, 0.06)

                        Rectangle {
                            x: 8
                            anchors.verticalCenter: parent.verticalCenter
                            width: 3
                            height: 24
                            radius: 2
                            color: Theme.accent
                        }
                        Column {
                            anchors.verticalCenter: parent.verticalCenter
                            anchors.left: parent.left
                            anchors.right: parent.right
                            anchors.leftMargin: 20
                            anchors.rightMargin: 28
                            spacing: 1

                            Text {
                                width: parent.width
                                text: root.nextLater !== null ? root.nextLater.title : ""
                                color: Theme.fg
                                font.family: Theme.fontFamilySans
                                font.pixelSize: 12
                                font.weight: Font.DemiBold
                                elide: Text.ElideRight
                            }
                            Text {
                                width: parent.width
                                text: root.laterText
                                color: Qt.alpha(Theme.fg, 0.6)
                                font.family: Theme.fontFamilySans
                                font.pixelSize: 10
                                elide: Text.ElideRight
                            }
                        }
                        Text {
                            anchors.right: parent.right
                            anchors.rightMargin: 10
                            anchors.verticalCenter: parent.verticalCenter
                            text: "󰅂"
                            color: Qt.alpha(Theme.fg, 0.4)
                            font.family: Theme.fontFamily
                            font.pixelSize: 14
                        }
                    }
                }
            }

            // ── Day: what is left to do ────────────────────────────────────
            Item {
                id: dayTab
                visible: root.tab === "day"
                y: 72
                width: panel.width
                height: panel.height - y

                // what is left to do: tasks and the schedule's blocks, scrolling when long
                Item {
                    id: todoList
                    x: 12
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

            // ── Focus: the task in hand and the time tracked today ──────────
            Item {
                id: focusTab
                visible: root.tab === "focus"
                y: 72
                width: panel.width
                height: panel.height - y

                // the task in focus: its timer and controls; with none, what the schedule offers
                Rectangle {
                    id: focusCard
                    x: 12
                    width: 232
                    height: parent.height - 12
                    radius: 12
                    color: Qt.alpha(Theme.fg, 0.06)

                    Column {
                        visible: root.focusOn
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.top: parent.top
                        anchors.margins: 14
                        spacing: 8

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

                                Row {
                                    spacing: 6

                                    Text {
                                        text: root.stripLabel
                                        color: Qt.alpha(Theme.fg, 0.55)
                                        font.family: Theme.fontFamilySans
                                        font.pixelSize: 11
                                    }
                                    Rectangle {
                                        anchors.verticalCenter: parent.verticalCenter
                                        width: 6
                                        height: 6
                                        radius: 3
                                        color: TaskFocus.running ? Theme.green : Theme.disabled
                                    }
                                }
                                Text {
                                    text: root.clockText
                                    color: Theme.fg
                                    font.family: Theme.fontFamilyNum
                                    font.pixelSize: 22
                                    font.bold: true
                                }
                            }
                        }

                        Text {
                            width: parent.width
                            text: TaskFocus.title
                            color: Theme.fg
                            font.family: Theme.fontFamilySans
                            font.pixelSize: 13
                            font.weight: Font.DemiBold
                            wrapMode: Text.WordWrap
                            maximumLineCount: 2
                            elide: Text.ElideRight
                        }
                        // a block of the schedule counts down, any other task shows its total
                        Text {
                            width: parent.width
                            text: root.plannedMin > 0 ? root.timeText
                                : "total " + root.totalText + (TaskFocus.item && TaskFocus.item.time !== "" ? "  ·  due " + TaskFocus.item.time : "")
                            color: Qt.alpha(Theme.fg, 0.5)
                            font.family: root.plannedMin > 0 ? Theme.fontFamilyNum : Theme.fontFamilySans
                            font.pixelSize: 11
                            elide: Text.ElideRight
                        }
                    }

                    Row {
                        visible: root.focusOn
                        anchors.left: parent.left
                        anchors.bottom: parent.bottom
                        anchors.margins: 12
                        spacing: 8

                        PillButton {
                            label: TaskFocus.running ? "Pause" : "Resume"
                            glyph: TaskFocus.running ? "󰏤" : "󰐊"
                            onClicked: TaskFocus.toggle()
                        }
                        PillButton {
                            label: "Done"
                            glyph: "󰄬"
                            main: true
                            onClicked: TaskFocus.complete()
                        }
                        IconButton {
                            width: 28
                            height: 28
                            glyph: "󰓛"
                            onClicked: TaskFocus.stop()
                        }
                    }

                    // nothing in focus
                    Column {
                        visible: !root.focusOn
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.top: parent.top
                        anchors.margins: 14
                        spacing: 8

                        Text {
                            text: "Nothing in focus"
                            color: Theme.fg
                            font.family: Theme.fontFamilySans
                            font.pixelSize: 13
                            font.weight: Font.DemiBold
                        }
                        Text {
                            width: parent.width
                            text: root.nextRow !== null ? "Next: " + root.nextRow.title : "Nothing left today"
                            color: Qt.alpha(Theme.fg, 0.6)
                            font.family: Theme.fontFamilySans
                            font.pixelSize: 12
                            wrapMode: Text.WordWrap
                            maximumLineCount: 2
                            elide: Text.ElideRight
                        }
                        PillButton {
                            visible: root.nextRow !== null
                            label: "Focus"
                            glyph: "󰐊"
                            main: true
                            onClicked: root.focusRow(root.nextRow)
                        }
                    }
                }

                // the time tracked today, most first, against the planned minutes where there are any
                Item {
                    id: trackedList
                    x: focusCard.x + focusCard.width + 14
                    width: panel.width - x - 18
                    height: parent.height - 12

                    Item {
                        id: trackedHead
                        width: parent.width
                        height: 20

                        Text {
                            text: "Tracked today"
                            color: Qt.alpha(Theme.fg, 0.5)
                            font.family: Theme.fontFamilySans
                            font.pixelSize: 11
                        }
                        Text {
                            anchors.right: parent.right
                            text: root.fmtMin(root.tracked.today) + " today  ·  " + root.fmtMin(root.tracked.week) + " this week"
                            color: Qt.alpha(Theme.fg, 0.5)
                            font.family: Theme.fontFamilyNum
                            font.pixelSize: 11
                        }
                    }

                    Column {
                        y: trackedHead.height + 4
                        width: parent.width

                        Repeater {
                            model: root.tracked.rows.slice(0, 5)

                            Item {
                                id: trackedRow
                                required property var modelData
                                width: parent.width
                                height: 28

                                Text {
                                    anchors.verticalCenter: parent.verticalCenter
                                    width: parent.width - amount.implicitWidth - 12
                                    text: trackedRow.modelData.title
                                    color: trackedRow.modelData.focused ? Theme.fg : Qt.alpha(Theme.fg, 0.8)
                                    font.family: Theme.fontFamilySans
                                    font.pixelSize: 12
                                    font.weight: trackedRow.modelData.focused ? Font.DemiBold : Font.Normal
                                    elide: Text.ElideRight
                                }
                                Text {
                                    id: amount
                                    anchors.right: parent.right
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: root.fmtMin(trackedRow.modelData.spent)
                                        + (trackedRow.modelData.planned > 0 ? " / " + root.fmtMin(trackedRow.modelData.planned) : "")
                                    color: Qt.alpha(Theme.fg, 0.6)
                                    font.family: Theme.fontFamilyNum
                                    font.pixelSize: 11
                                }
                            }
                        }
                    }

                    Text {
                        visible: root.tracked.rows.length === 0
                        y: trackedHead.height + 12
                        text: "No time tracked today"
                        color: Qt.alpha(Theme.fg, 0.4)
                        font.family: Theme.fontFamilySans
                        font.pixelSize: 12
                    }
                }
            }

            // ── Week: the schedule's grid ──────────────────────────────────
            WeekGrid {
                visible: root.tab === "week"
                x: 12
                y: 72
                width: panel.width - 24
                height: panel.height - y - 10
            }
        }
    }
}
