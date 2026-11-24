import QtQuick
import QtQuick.Effects
import Quickshell
import Quickshell.Wayland
import Quickshell.Hyprland
import Quickshell.Services.Notifications
import Quickshell.Services.Pipewire
import Quickshell.Services.Mpris
import "../../services"
import "../../services/menu"
import "../notch"
import "../bar/media"
import "../drawer"
import "../bar"

// The focus notch: the bar's center pill grows into the task timer and, on a
// click, into a panel with a row of page buttons along the top. Hover the pill
// and it widens into a strip. With a task in focus the strip shows it, the time
// spent on it so far (or, for a block of the schedule, what is left of it and
// when it ends), and pause and done. With nothing in focus it shows the clock,
// the date, the now-playing track and the workspaces. Click the strip (or run
// `qs ipc call focusnotch toggle`) and it opens further. A header switches between
// Home, Work, Ports and Usage; Work holds the Day, Week and Focus pages, and a small
// switch on a row under the tabs picks between them:
//   Home   the now-playing card on the left, and the day on the right: the date,
//          what is on now and what comes next. The card's two buttons next to the
//          transport switch it to the playing sources, or to the audio output.
//   Day    what is left to do: todo.md's tasks together with today's blocks from
//          schedule.md. A click puts a row in focus (it does not tick it), the
//          check on a hovered row ticks it, and the box at the bottom adds a task
//          to today, typed the way todo.md has it.
//   Week   the schedule's grid, with today and the block that is on now marked.
//   Focus  the task in hand: its timer, pause, stop and done, and the time tracked today.
//   Ports  what is listening on this machine, and which of it the network can reach.
//   Usage  time per app for today, this week or this month, charted by hour or by day.
//   Buds   the battery of the Galaxy Buds, left, right and case, and how they are worn.
//   Tray   favourite files as a carousel: a search, a click opens one with xdg-open, and a
//          file dropped on the page is kept. Kept apart from the queue of the Share page.
// The gear at the right of the header, on every page, opens the control panel (ControlPage):
// a page with no tab, narrower than the others and as tall as its rows, and the gear leaves
// it again. `qs ipc call drawer toggle` opens it too.
// The strip closes when the pointer leaves it; the open panel closes on Escape
// or a click outside.
PanelWindow {
    id: root

    screen: PillState.originScreen
    visible: false

    // the whole height: the control page is as tall as its rows. The mask keeps the
    // rest of the screen usable.
    anchors {
        top: true
        bottom: true
        left: true
        right: true
    }

    color: "transparent"
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.layer: WlrLayer.Overlay
    // the pinned strip and the open panel hold the keys, so Escape reaches them; on demand focus
    // was dropped as soon as the pointer left the strip
    WlrLayershell.keyboardFocus: root.stage !== "" ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None
    WlrLayershell.namespace: "quickshell-focusnotch"

    // the strip only takes input on the card, so the screen below stays usable;
    // the open panel also takes the band around it, to catch a click outside
    mask: Region { item: root.stage === "open" ? catcher : card }

    // ── Geometry ───────────────────────────────────────────────────────────
    readonly property int hoverW: 560
    readonly property int hoverH: 88
    readonly property int openW: 580
    readonly property int openH: 260
    // The card's size on the open panel. The pages share openW x openH; the control page is
    // narrower and as tall as its rows. The card eases from one to the other, and the
    // pages stay at their own size under it, so none of them is stretched on the way.
    readonly property bool onControl: tab === "control"
    property real shownW: onControl ? controlPage.width : openW
    property real shownH: onControl ? controlPage.y + controlPage.height : openH
    // only a change on an open panel is eased; opening goes straight to the size
    Behavior on shownW {
        enabled: root.expand > 0.99
        NumberAnimation { duration: 150; easing.type: Easing.OutCubic }
    }
    Behavior on shownH {
        enabled: root.expand > 0.99
        NumberAnimation { duration: 150; easing.type: Easing.OutCubic }
    }

    // "" closed, "hover" the strip, "open" the full panel
    property string stage: ""
    // the open panel's page: "home", "day", "week", "focus", "ports", "usage", "share", "buds", "tray" or "control", remembered
    // across openings (the control page is not: it is left when the panel closes)
    // a page the settings turn off is not shown; the first one that is on takes its place
    readonly property string tab: FocusNotchState.pageOn(FocusNotchState.page) ? FocusNotchState.page : (pages[0] ?? "home")
    readonly property var pages: ["home", "day", "week", "focus", "ports", "usage", "share", "buds", "tray"].filter(FocusNotchState.pageOn)
    // the strip's tabs, minus the pages the settings turn off
    readonly property var tabList: [{ key: "home", glyph: "󰋜", name: "Home" },
                                    { key: "work", glyph: "󰸗", name: "Work" },
                                    { key: "ports", glyph: "󰈀", name: "Ports" },
                                    { key: "usage", glyph: "󰄧", name: "Usage" },
                                    { key: "share", glyph: "󰈔", name: "Share" },
                                    { key: "buds", glyph: "󰋋", name: "Buds" },
                                    { key: "tray", glyph: "󰉋", name: "Tray" }].filter(t => FocusNotchState.pageOn(t.key))
    readonly property int pageIndex: Math.max(0, pages.indexOf(tab))
    // Work is Day or Week; the Work tab returns to the one last shown
    property string lastWork: "day"
    readonly property bool onWork: tab === "day" || tab === "week" || tab === "focus"
    // reads `tab` itself and not `onWork`: this handler can run before onWork has been
    // re-evaluated, and then leaving Work for Home would store "home" as the Work page
    onTabChanged: if (tab === "day" || tab === "week" || tab === "focus") lastWork = tab
    // wraps at both ends
    function stepPage(delta) {
        // the control page is not in the row of pages
        if (onControl)
            return
        const n = pages.length
        FocusNotchState.setPage(pages[(pageIndex + delta + n) % n])
    }
    // ss only runs while the Ports page is on screen
    Binding {
        target: Ports
        property: "watching"
        value: root.stage === "open" && root.tab === "ports"
    }
    // GalaxyBudsClient only runs while the Buds page is on screen
    Binding {
        target: Buds
        property: "watching"
        value: root.stage === "open" && root.tab === "buds"
    }
    onStageChanged: if (stage === "open") keyHost.forceActiveFocus()
    // 0 = the bar pill, 1 = the strip; 0 = the strip, 1 = the full panel
    property real grow: 0
    property real expand: 0
    // the card the previous panel gave up; the panel grows from it instead of from the strip
    property real takeW: 0
    property real takeH: 0

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
    readonly property int plannedMin: {
    if (!focusOn) return 0;
    // Check if the focused task has an explicit estimate (e.g. from =45m), otherwise check schedule
    if (TaskFocus.item && TaskFocus.item.estimate > 0)
        return TaskFocus.item.estimate;
    return Schedule.minutesFor(TaskFocus.title);
    }
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
    // today and for this week, Sunday to Saturday like the Usage page. The
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

    // Free time: what is left before bedtime (the `bed` key of the [sleep] table) once the
    // open rows are done. A block of the schedule counts what is left of its length after
    // the time spent on it; a block that has run over counts nothing, so it never makes
    // the total negative. No bedtime, or past it, and there is nothing to show.
    readonly property int bedMin: SleepReminder.bedAt !== "" ? minutesOf(SleepReminder.bedAt) : -1
    readonly property int plannedLeftMin: {
        let sum = 0
        for (const r of rows) {
            if (r.end < 0)
                continue
            const spent = (r.task ? r.task.spent : 0) + (TaskFocus.sameTask(r) ? elapsedMin : 0)
            sum += Math.max(0, r.end - r.start - spent)
        }
        return sum
    }
    readonly property string freeText: {
        if (bedMin < 0 || Schedule.nowMin >= bedMin)
            return ""
        const m = bedMin - Schedule.nowMin - plannedLeftMin
        return m <= 0 ? "no time free" : fmtHours(m) + " free"
    }
    readonly property string leftText: rows.length + " left" + (freeText !== "" ? "  ·  " + freeText : "")

    function fmtHours(m) {
        const h = Math.floor(m / 60)
        return h > 0 ? h + " h" + (m % 60 > 0 ? " " + m % 60 + " m" : "") : m + " m"
    }

    // A colour of its own for a row without a priority: the hue comes from the title, so
    // it stays the same from one refresh to the next, with the accent's saturation and lightness.
    function titleTint(title) {
        let h = 0
        for (let i = 0; i < title.length; i++)
            h = (h * 31 + title.charCodeAt(i)) % 360
        return Qt.hsla(h / 360, Theme.accent.hslSaturation, Theme.accent.hslLightness, 1)
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
// the right-hand label of a row: the hour for today's, the date for overdue, or the estimate if no time is set
    function whenText(r) {
        if (r.late) 
            return Qt.formatDate(Todo.toDate(r.due), "d MMM")
        if (r.time !== "") 
            return r.time
        // Fall back to showing the task's estimate/duration if it exists
        const est = r.task && r.task.estimate > 0 ? r.task.estimate : Schedule.minutesFor(r.title)
        return est > 0 ? fmtMin(est) : ""
    }

    // starts timing a row; a block of the schedule becomes a task first
    function focusRow(r) {
        if (r.kind === "slot")
            Todo.materialize(r, false)
        TaskFocus.focus(r)
    }

    // A task clears once half its expected time is spent. Expected time is the
    // =estimate typed on the task, else the length of its schedule block; a task
    // with neither clears at any time.
    function clearableAt(planned, spentMin) {
        return planned === 0 || spentMin >= planned / 2
    }

    // time spent on a row, including the live run when it is the task in focus
    function rowSpentMin(r) {
        return (r.task ? r.task.spent : 0) + (TaskFocus.sameTask(r) ? TaskFocus.elapsedMs / 60000 : 0)
    }

    function rowClearable(r) {
        const planned = r.task && r.task.estimate > 0 ? r.task.estimate : Schedule.minutesFor(r.title)
        return clearableAt(planned, rowSpentMin(r))
    }

    readonly property bool focusClearable: focusOn && clearableAt(
        TaskFocus.item && TaskFocus.item.estimate > 0 ? TaskFocus.item.estimate : Schedule.minutesFor(TaskFocus.title),
        (TaskFocus.item ? TaskFocus.item.spent : 0) + TaskFocus.elapsedMs / 60000)

    // ticks a row; a block of the schedule is added to the file already ticked
    function tickRow(r) {
        if (!rowClearable(r))
            return
        if (r.kind === "slot")
            Todo.materialize(r, true)
        else
            Todo.toggle(r.task)
    }

    // ── Open / close ───────────────────────────────────────────────────────
    // the pill is free, or still ours while the strip closes, so a reopen is not held back
    readonly property bool canTake: (PillState.owner === "" || PillState.owner === "focus")
        && !Overview.open && FocusNotchState.available

    function goTo(g, e) {
        growAnim.stop()
        expandAnim.stop()
        growAnim.to = g
        expandAnim.to = e
        growAnim.start()
        expandAnim.start()
    }

    // A hovered strip closes when the pointer leaves it after having been in it, or after a
    // moment when the pointer never reaches it (an accidental hover over the pill). A new
    // surface gets no pointer until it moves, so a leave before any entry is not a leave.
    property bool stripEntered: false
    Timer {
        id: hoverLeave
        interval: 120
        onTriggered: if (root.stage === "hover" && !cardHover.hovered) root.close()
    }
    Timer {
        id: hoverIdle
        interval: 1200
        onTriggered: if (root.stage === "hover" && !root.stripEntered) root.close()
    }

    function show(next) {
        if (!PillState.claim("focus"))
            return
        // only a fresh open plays, not the hover strip growing into the panel
        if (stage === "")
            Sounds.play("open-notch")
        stripEntered = cardHover.hovered
        hoverIdle.stop()
        hoverLeave.stop()
        if (next === "hover")
            hoverIdle.restart()
        // a card the previous panel gave up: grow from it, with the strip kept hidden
        const from = PillState.takeOver()
        takeW = from.taken ? from.w : 0
        takeH = from.taken ? from.h : 0
        // the strip's clock fades in on open
        if (!focusOn)
            fadeIn.restart()
        visible = true
        stage = next
        goTo(from.taken ? 0 : 1, next === "open" ? 1 : 0)
    }

    // another panel took the pill: hand this card over and step aside at once
    function giveWay() {
        PillState.takeoverW = card.width
        PillState.takeoverH = card.height
        takeW = 0
        takeH = 0
        growAnim.stop()
        expandAnim.stop()
        grow = 0
        expand = 0
        stage = ""
        FocusNotchState.openRequested = false
        hoverIdle.stop()
        hoverLeave.stop()
        visible = false
    }

    function close() {
        if (stage === "")
            return
        Sounds.play("close-notch")
        stage = ""
        FocusNotchState.openRequested = false
        hoverIdle.stop()
        hoverLeave.stop()
        if (PillState.owner === "focus")
            PillState.returning = true
        // the strip's clock fades out on close, the reverse of the fade in
        fadeIn.stop()
        if (!focusOn)
            fadeOut.restart()
        // closing shrinks back into the strip, as it does when it was not a takeover
        takeW = 0
        takeH = 0
        goTo(0, 0)
    }

    NumberAnimation {
        id: growAnim
        target: root
        property: "grow"
        duration: 180
        // back out: the strip overshoots its size and settles, so the open reads as a spring
        easing.type: Easing.OutBack
        easing.overshoot: 2.5
        onFinished: {
            if (root.stage === "" && root.grow < 0.01) {
                root.visible = false
                FocusNotchState.leaveControl()
                if (PillState.owner === "focus")
                    PillState.owner = ""
            }
        }
    }

    NumberAnimation {
        id: expandAnim
        target: root
        property: "expand"
        duration: PillState.morphMs
        easing.type: PillState.openEase
        easing.period: PillState.easePeriod
    }


    Connections {
        target: FocusNotchState
        function onPillHoveredChanged() {
            // a strip already showing stays as it is; the strip's own leave or the idle timer closes it
            if (FocusNotchState.pillHovered && root.stage === "" && root.canTake)
                root.show("hover")
        }
        function onOpenRequestedChanged() {
            // the notch is off or has no page on: a request to open it is dropped
            if (FocusNotchState.openRequested && !FocusNotchState.available) {
                FocusNotchState.openRequested = false
            } else if (FocusNotchState.openRequested) {
                // the control panel takes the pill from another panel, as it did as a window
                if (root.stage !== "open" && (root.canTake || root.stage === "hover"
                        || FocusNotchState.page === "control"))
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
                // a panel took the pill: hand our card over, or shrink back when nothing did
                if (PillState.owner !== "") root.giveWay()
                else root.close()
            }
        }
    }

    // a click in the band outside the card closes the open panel
    MouseArea {
        id: catcher
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        height: PillState.pillTop + root.shownH + 12
        onClicked: root.close()
    }

    Notch {
        bodyWidth: card.width
        bodyHeight: card.height + 18
        x: card.x - bodyX
        y: card.y
    }

    Rectangle {
        id: card

        // grow overshoots past 1 and dips below 0 on the way; the strip never draws below the pill
        readonly property real stripW: PillState.pillWidth + (root.hoverW - PillState.pillWidth) * Math.max(0, root.grow)
        readonly property real stripH: PillState.pillHeight + (root.hoverH - PillState.pillHeight) * Math.max(0, root.grow)

        readonly property real startW: root.takeW > 0 ? root.takeW : stripW
        readonly property real startH: root.takeH > 0 ? root.takeH : stripH

        width: startW + (root.shownW - startW) * Math.max(0, root.expand)
        height: startH + (root.shownH - startH) * Math.max(0, root.expand)
        x: (root.width - width) / 2
        y: PillState.pillTop
        color: "transparent"
        clip: true

        HoverHandler {
            id: cardHover
            onHoveredChanged: {
                if (hovered) {
                    root.stripEntered = true
                    hoverIdle.stop()
                    hoverLeave.stop()
                } else if (root.stage === "hover") {
                    hoverLeave.restart()
                }
            }
        }

        // a click on the hovered strip opens the panel; one on the open panel stays on it
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
            Keys.onEscapePressed: {
                // a list on the control page goes back to the switches first
                if (!(root.onControl && controlPage.leaveView()))
                    root.close()
            }
            // Left, Right, Up, Down, Enter, X and S are the tray's, on its page; Tab and Shift+Tab move between pages
            Keys.onLeftPressed: event => {
                if (root.tab === "tray") {
                    trayPage.stepBy(-1)
                    event.accepted = true
                }
            }
            Keys.onRightPressed: event => {
                if (root.tab === "tray") {
                    trayPage.stepBy(1)
                    event.accepted = true
                }
            }
            Keys.onReturnPressed: event => {
                if (root.tab === "tray") {
                    trayPage.openCurrent()
                    event.accepted = true
                }
            }
            // X takes the centre favourite off the tray, S cycles its sort, Backspace goes up a
            // folder, Home and End jump to the ends; typing in the search box never reaches here
            Keys.onPressed: event => {
                if (root.tab !== "tray" || event.modifiers !== Qt.NoModifier)
                    return
                if (event.key === Qt.Key_Backspace) {
                    trayPage.up()
                    event.accepted = true
                } else if (event.key === Qt.Key_Home) {
                    trayPage.stepTo(0)
                    event.accepted = true
                } else if (event.key === Qt.Key_End) {
                    trayPage.stepTo(trayPage.shown.length - 1)
                    event.accepted = true
                } else if (event.key === Qt.Key_X) {
                    trayPage.removeCurrent()
                    event.accepted = true
                } else if (event.key === Qt.Key_S) {
                    trayPage.cycleSort()
                    event.accepted = true
                }
            }
            Keys.onUpPressed: event => {
                if (root.tab === "tray") {
                    trayPage.up()
                    event.accepted = true
                }
            }
            Keys.onDownPressed: event => {
                if (root.tab === "tray") {
                    trayPage.enterCurrent()
                    event.accepted = true
                }
            }
            Keys.onTabPressed: event => {
                root.stepPage(1)
                event.accepted = true
            }
            Keys.onBacktabPressed: event => {
                root.stepPage(-1)
                event.accepted = true
            }
        }

        // ── The strip ──────────────────────────────────────────────────────
        Item {
            id: strip
            width: root.hoverW
            height: root.hoverH
            x: (card.width - width) / 2
            opacity: Math.max(0, (root.grow - 0.5) * 2) * Math.max(0, 1 - root.expand * 2) * (root.focusOn ? 1 : 0)
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
                        visible: root.focusClearable
                        glyph: "󰄬"
                        main: true
                        onClicked: TaskFocus.complete()
                    }
                }
            }
        }

        // ── The idle strip: shown on hover while nothing is in focus ───────
        Item {
            id: idleStrip
            anchors.horizontalCenter: parent.horizontalCenter
            width: root.hoverW
            height: root.hoverH + 10
            x: (card.width - width) / 2
            opacity: Math.max(0, (root.grow - 0.5) * 2) * Math.max(0, 1 - root.expand * 2) * (root.focusOn ? 0 : 1)
            visible: opacity > 0

            // the clock ticks on the minute, not every second: no polling
            SystemClock {
                id: idleClock
                precision: SystemClock.Minutes
            }
            // the same MPRIS state the bar's media wave and the Home page read
            MediaState { id: idleMedia }

            Column {
                anchors.left: parent.left
                anchors.leftMargin: 22
                anchors.verticalCenter: parent.verticalCenter
                spacing: 2
                opacity: root.clockShown

                Text {
                    text: Qt.formatDateTime(idleClock.date, UserSettings.clockFormat)
                    color: Theme.fg
                    // SF Rounded bold, as the bar's and the lock's clock, so the two read as one clock
                    font.family: Theme.fontFamilyRounded
                    font.pixelSize: 34
                    font.bold: true
                }
                Text {
                    text: Qt.formatDate(idleClock.date, "dddd, MMMM d")
                    color: Qt.alpha(Theme.fg, 0.55)
                    font.family: Theme.fontFamilySans
                    font.pixelSize: 11
                }
            }

            Row {
                id: idleMediaRow
                anchors.right: parent.right
                anchors.rightMargin: 22
                anchors.top: parent.top
                anchors.topMargin: 14
                spacing: 10

                Column {
                    anchors.verticalCenter: parent.verticalCenter
                    width: 130
                    spacing: 2

                    Text {
                        width: parent.width
                        text: idleMedia.present ? (idleMedia.player?.trackTitle ?? "") : "Nothing playing"
                        horizontalAlignment: Text.AlignRight
                        color: idleMedia.present ? Theme.fg : Qt.alpha(Theme.fg, 0.5)
                        font.family: Theme.fontFamilySans
                        font.pixelSize: 13
                        font.weight: idleMedia.present ? Font.DemiBold : Font.Normal
                        elide: Text.ElideRight
                    }
                    Text {
                        width: parent.width
                        visible: idleMedia.present
                        text: idleMedia.artistText
                        horizontalAlignment: Text.AlignRight
                        color: Qt.alpha(Theme.fg, 0.6)
                        font.family: Theme.fontFamilySans
                        font.pixelSize: 11
                        elide: Text.ElideRight
                    }
                }

                Rectangle {
                    id: idleArt
                    anchors.verticalCenter: parent.verticalCenter
                    width: 36
                    height: 36
                    radius: 8
                    color: Qt.alpha(Theme.fg, 0.08)

                    // rounding by mask, since clip only cuts square corners
                    Item {
                        id: idleArtMask
                        anchors.fill: parent
                        visible: false
                        layer.enabled: true
                        Rectangle { anchors.fill: parent; radius: idleArt.radius; color: "white" }
                    }
                    Image {
                        anchors.fill: parent
                        source: idleMedia.player?.trackArtUrl ?? ""
                        fillMode: Image.PreserveAspectCrop
                        visible: status === Image.Ready
                        layer.enabled: true
                        layer.effect: MultiEffect {
                            maskEnabled: true
                            maskSource: idleArtMask
                        }
                    }
                }
            }

            // a thin rule under the media, the horizontal counterpart of the old vertical divider
            Rectangle {
                anchors.right: parent.right
                anchors.rightMargin: 22
                anchors.top: idleMediaRow.bottom
                anchors.topMargin: 8
                width: idleMediaRow.width
                height: 1
                color: Qt.alpha(Theme.fg, 0.12)
            }

            // the workspaces as dots for this screen; the focused one stretches into a bar
            Wm {
                id: dotWm
                outputName: PillState.originName
            }
            Row {
                anchors.right: parent.right
                anchors.rightMargin: 22
                anchors.bottom: parent.bottom
                anchors.bottomMargin: 14
                spacing: 6

                Repeater {
                    model: dotWm.workspaces
                        .slice()
                        .sort((a, b) => a.index - b.index)
                        .slice(0, 5)

                    Rectangle {
                        id: dot

                        required property var modelData
                        readonly property bool focused: modelData.focused

                        anchors.verticalCenter: parent.verticalCenter
                        width: focused ? 16 : 6
                        height: 6
                        radius: 3
                        color: focused ? Theme.accent
                            : modelData.occupied ? Qt.alpha(Theme.accent, 0.6)
                            : Qt.alpha(Theme.fg, 0.22)

                        Behavior on width { NumberAnimation { duration: 200; easing.type: Easing.OutCubic } }
                        Behavior on color { ColorAnimation { duration: 150 } }

                        // the dot is small, so the hit area runs a few pixels past it
                        MouseArea {
                            anchors.fill: parent
                            anchors.margins: -4
                            cursorShape: Qt.PointingHandCursor
                            onClicked: Hyprland.dispatch('hl.dsp.focus({ workspace = "' + dot.modelData.id + '" })')
                        }
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
            // It is as wide as the page, so the gear stays at the corner on the narrow one.
            Item {
                x: (panel.width - root.shownW) / 2 + 18
                y: 8
                width: root.shownW - 36
                height: 30

                Row {
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 2

                    Repeater {
                        model: root.tabList

                        Rectangle {
                            id: tabButton
                            required property var modelData
                            // Work is on for all three of its pages
                            readonly property bool on: modelData.key === "work"
                                ? root.onWork : root.tab === modelData.key

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
                                    FocusNotchState.setPage(tabButton.modelData.key === "work" ? root.lastWork : tabButton.modelData.key)
                                    keyHost.forceActiveFocus()
                                }
                            }
                        }
                    }
                }

                // on Work: what is playing
                Row {
                    anchors.right: gear.left
                    anchors.rightMargin: 6
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 6
                    opacity: root.onWork ? 1 : 0
                    visible: opacity > 0
                    Behavior on opacity { NumberAnimation { duration: 150 } }

                    Rectangle {
                        visible: media.present
                        anchors.verticalCenter: parent.verticalCenter
                        height: 24
                        width: chipRow.implicitWidth + 18
                        radius: 12
                        color: Qt.alpha(Theme.fg, 0.08)

                        Row {
                            id: chipRow
                            anchors.centerIn: parent
                            spacing: 7

                            // the cover as a small dot, rounded by mask like the player's
                            Item {
                                anchors.verticalCenter: parent.verticalCenter
                                width: 14
                                height: 14

                                Rectangle { anchors.fill: parent; radius: 7; color: Qt.alpha(Theme.accent, 0.5) }
                                Item {
                                    id: chipMask
                                    anchors.fill: parent
                                    visible: false
                                    layer.enabled: true
                                    Rectangle { anchors.fill: parent; radius: 7; color: "white" }
                                }
                                Image {
                                    anchors.fill: parent
                                    source: media.player?.trackArtUrl ?? ""
                                    fillMode: Image.PreserveAspectCrop
                                    visible: status === Image.Ready
                                    layer.enabled: true
                                    layer.effect: MultiEffect {
                                        maskEnabled: true
                                        maskSource: chipMask
                                    }
                                }
                            }
                            Text {
                                anchors.verticalCenter: parent.verticalCenter
                                width: Math.min(implicitWidth, 120)
                                text: media.player?.trackTitle ?? ""
                                color: Theme.fg
                                font.family: Theme.fontFamilySans
                                font.pixelSize: 11
                                elide: Text.ElideRight
                            }
                            EqBars {
                                anchors.verticalCenter: parent.verticalCenter
                                playing: media.playing
                            }
                        }
                    }
                }

                // the gear, on every page: the control panel, and back from it
                Rectangle {
                    id: gear
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    width: 24
                    height: 24
                    radius: 12
                    color: gearMouse.containsMouse ? Qt.alpha(Theme.fg, 0.2) : Qt.alpha(Theme.fg, 0.08)
                    Behavior on color { ColorAnimation { duration: 120 } }

                    Text {
                        anchors.centerIn: parent
                        text: "󰒓"
                        color: root.onControl ? Theme.accent : Qt.alpha(Theme.fg, 0.7)
                        font.family: Theme.fontFamily
                        font.pixelSize: 13
                    }
                    MouseArea {
                        id: gearMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            FocusNotchState.toggleGear()
                            keyHost.forceActiveFocus()
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
                opacity: root.onWork ? 1 : 0
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

                // what the media card shows: the player, its playing sources, or the
                // outputs; back to the player whenever the Home page is left
                property string mediaView: "player"
                onVisibleChanged: if (!visible) mediaView = "player"

                // the outputs, bound only while their list is on screen
                readonly property var sinks: Pipewire.nodes.values.filter(n => n.isSink && !n.isStream)

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
                        visible: homeTab.mediaView === "player"
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

                    // fades out while the sources or output view is on, as the card's content does not
                    EqBars {
                        anchors.right: mediaTop.right
                        anchors.verticalCenter: mediaTop.verticalCenter
                        opacity: media.present && homeTab.mediaView === "player" ? 1 : 0
                        visible: opacity > 0
                        playing: media.playing

                        Behavior on opacity { NumberAnimation { duration: 150; easing.type: Easing.OutQuad } }
                    }

                    // elapsed, a thin track, and the time left
                    Item {
                        id: progress
                        visible: homeTab.mediaView === "player"
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.top: mediaTop.bottom
                        anchors.leftMargin: 14
                        anchors.rightMargin: 14
                        anchors.topMargin: 18
                        height: 14

                        // while dragging the track shows the scrubbed spot; it seeks on release
                        property bool scrubbing: false
                        property real scrubFrac: 0
                        readonly property real shownPos: scrubbing ? scrubFrac * media.len : media.pos
                        readonly property real shownFrac: media.timed ? Math.min(1, shownPos / media.len) : 0

                        Text {
                            id: elapsed
                            anchors.left: parent.left
                            anchors.verticalCenter: parent.verticalCenter
                            text: media.present ? media.fmt(progress.shownPos) : ""
                            color: Qt.alpha(Theme.fg, 0.6)
                            font.family: Theme.fontFamilyNum
                            font.pixelSize: 11
                        }
                        Text {
                            id: remaining
                            anchors.right: parent.right
                            anchors.verticalCenter: parent.verticalCenter
                            visible: media.timed
                            text: media.timed ? "-" + media.fmt(media.len - progress.shownPos) : ""
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
                                width: parent.width * progress.shownFrac
                            }

                            // the hit area runs a few pixels past the 4 px track, so it is easy to grab
                            MouseArea {
                                id: seekArea
                                anchors.fill: parent
                                anchors.margins: -8
                                enabled: media.timed && (media.player?.canSeek ?? false)
                                cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor

                                function fracAt(mx) {
                                    const x = mapToItem(parent, mx, 0).x
                                    return Math.max(0, Math.min(1, x / parent.width))
                                }
                                onPressed: mouse => {
                                    progress.scrubFrac = fracAt(mouse.x)
                                    progress.scrubbing = true
                                }
                                onPositionChanged: mouse => {
                                    if (progress.scrubbing)
                                        progress.scrubFrac = fracAt(mouse.x)
                                }
                                onReleased: {
                                    media.seek(progress.scrubFrac)
                                    progress.scrubbing = false
                                }
                                onCanceled: progress.scrubbing = false
                            }
                        }
                    }

                    // previous, play or pause, next: fixed cells, so the three share one centre line
                    Row {
                        visible: homeTab.mediaView === "player"
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

                        // playing sources on the left, output on the right
                        Transport {
                            glyph: "≡"
                            glyphSize: 18
                            onTapped: homeTab.mediaView = "sources"
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
                        Transport {
                            glyph: "󰕾"
                            glyphSize: 18
                            onTapped: homeTab.mediaView = "output"
                        }
                    }
                }

                // ── Playing sources: the MPRIS players; picking one pins it to the card ──
                Item {
                    id: sourcesView
                    visible: homeTab.mediaView === "sources"
                    x: mediaCard.x
                    y: mediaCard.y
                    width: mediaCard.width
                    height: mediaCard.height

                    Text {
                        id: sourcesBack
                        x: 14
                        y: 12
                        text: "‹  Playing sources"
                        color: backSources.containsMouse ? Theme.accent : Theme.fg
                        font.family: Theme.fontFamilySans
                        font.pixelSize: 13
                        font.weight: Font.DemiBold

                        MouseArea {
                            id: backSources
                            anchors.fill: parent
                            anchors.margins: -6
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: homeTab.mediaView = "player"
                        }
                    }

                    ListView {
                        x: 14
                        y: sourcesBack.y + sourcesBack.height + 10
                        width: parent.width - 28
                        height: parent.height - y - 8
                        clip: true
                        spacing: 4
                        boundsBehavior: Flickable.StopAtBounds
                        model: Mpris.players.values

                        // nothing to choose from until a player is running
                        Text {
                            anchors.centerIn: parent
                            visible: parent.count === 0
                            text: "No player running"
                            color: Qt.alpha(Theme.fg, 0.5)
                            font.family: Theme.fontFamilySans
                            font.pixelSize: 12
                        }

                        delegate: Rectangle {
                            id: sourceRow
                            required property var modelData
                            readonly property bool current: media.player === modelData
                            readonly property bool playing: modelData.playbackState === MprisPlaybackState.Playing

                            width: ListView.view.width
                            height: 44
                            radius: 8
                            color: current ? Qt.alpha(Theme.fg, 0.1)
                                 : sourceMouse.containsMouse ? Qt.alpha(Theme.fg, 0.05) : "transparent"

                            Column {
                                anchors.left: parent.left
                                anchors.right: sourceState.left
                                anchors.leftMargin: 12
                                anchors.rightMargin: 8
                                anchors.verticalCenter: parent.verticalCenter
                                spacing: 2

                                Text {
                                    width: parent.width
                                    text: sourceRow.modelData.trackTitle || sourceRow.modelData.identity
                                    elide: Text.ElideRight
                                    color: Theme.fg
                                    font.family: Theme.fontFamilySans
                                    font.pixelSize: 13
                                    font.weight: sourceRow.current ? Font.DemiBold : Font.Normal
                                }
                                Text {
                                    width: parent.width
                                    text: sourceRow.modelData.identity
                                    elide: Text.ElideRight
                                    color: Qt.alpha(Theme.fg, 0.5)
                                    font.family: Theme.fontFamilySans
                                    font.pixelSize: 11
                                }
                            }
                            Text {
                                id: sourceState
                                anchors.right: parent.right
                                anchors.rightMargin: 12
                                anchors.verticalCenter: parent.verticalCenter
                                text: sourceRow.playing ? "󰕾" : "󰏤"
                                color: sourceRow.playing ? Theme.accent : Qt.alpha(Theme.fg, 0.4)
                                font.family: Theme.fontFamily
                                font.pixelSize: 14
                            }

                            MouseArea {
                                id: sourceMouse
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: {
                                    media.manual = sourceRow.modelData
                                    homeTab.mediaView = "player"
                                }
                            }
                        }
                    }
                }

                // ── Output: the audio sinks, and the volume of the default one ──
                Item {
                    id: outputView
                    visible: homeTab.mediaView === "output"
                    x: mediaCard.x
                    y: mediaCard.y
                    width: mediaCard.width
                    height: mediaCard.height

                    // bound only while the list is shown, so the sinks report their names
                    PwObjectTracker {
                        objects: outputView.visible ? homeTab.sinks : []
                    }

                    Text {
                        id: outputBack
                        x: 14
                        y: 12
                        text: "‹  Output"
                        color: backOutput.containsMouse ? Theme.accent : Theme.fg
                        font.family: Theme.fontFamilySans
                        font.pixelSize: 13
                        font.weight: Font.DemiBold

                        MouseArea {
                            id: backOutput
                            anchors.fill: parent
                            anchors.margins: -6
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: homeTab.mediaView = "player"
                        }
                    }

                    Column {
                        id: sinkList
                        x: 14
                        y: outputBack.y + outputBack.height + 10
                        width: outputView.width - 28
                        spacing: 2

                        Repeater {
                            model: homeTab.sinks

                            Rectangle {
                                id: sinkRow
                                required property var modelData
                                readonly property bool current: Pipewire.defaultAudioSink === modelData

                                width: sinkList.width
                                height: 32
                                radius: 8
                                color: sinkMouse.containsMouse ? Qt.alpha(Theme.fg, 0.05) : "transparent"

                                Text {
                                    anchors.left: parent.left
                                    anchors.leftMargin: 12
                                    anchors.right: sinkCheck.left
                                    anchors.rightMargin: 8
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: sinkRow.modelData.description || sinkRow.modelData.name
                                    elide: Text.ElideRight
                                    color: sinkRow.current ? Theme.fg : Qt.alpha(Theme.fg, 0.7)
                                    font.family: Theme.fontFamilySans
                                    font.pixelSize: 13
                                    font.weight: sinkRow.current ? Font.DemiBold : Font.Normal
                                }
                                Text {
                                    id: sinkCheck
                                    anchors.right: parent.right
                                    anchors.rightMargin: 12
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: sinkRow.current ? "✓" : ""
                                    color: Theme.accent
                                    font.family: Theme.fontFamilySans
                                    font.pixelSize: 13
                                }

                                MouseArea {
                                    id: sinkMouse
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: Pipewire.preferredDefaultAudioSink = sinkRow.modelData
                                }
                            }
                        }
                    }

                    // the default output's volume, under the list
                    Item {
                        id: volumeRow
                        x: 14
                        width: outputView.width - 28
                        height: 20
                        y: outputView.height - height - 14
                        visible: Volume.audio !== null

                        Text {
                            id: volIcon
                            anchors.left: parent.left
                            anchors.verticalCenter: parent.verticalCenter
                            text: "󰕾"
                            color: Qt.alpha(Theme.fg, 0.6)
                            font.family: Theme.fontFamily
                            font.pixelSize: 14
                        }
                        Rectangle {
                            id: volTrack
                            anchors.left: volIcon.right
                            anchors.leftMargin: 10
                            anchors.right: volReadout.left
                            anchors.rightMargin: 10
                            anchors.verticalCenter: parent.verticalCenter
                            height: 4
                            radius: 2
                            color: Qt.alpha(Theme.fg, 0.12)

                            Rectangle {
                                anchors.left: parent.left
                                anchors.top: parent.top
                                anchors.bottom: parent.bottom
                                width: parent.width * Math.max(0, Math.min(1, Volume.audio ? Volume.audio.volume : 0))
                                radius: parent.radius
                                color: Theme.accent
                            }
                            // taller than the track, so it is easy to hit
                            MouseArea {
                                anchors.fill: parent
                                anchors.topMargin: -8
                                anchors.bottomMargin: -8
                                cursorShape: Qt.PointingHandCursor
                                function set(x) {
                                    if (Volume.audio)
                                        Volume.audio.volume = Math.max(0, Math.min(1, x / width))
                                }
                                onPressed: m => set(m.x)
                                onPositionChanged: m => { if (pressed) set(m.x) }
                            }
                        }
                        Text {
                            id: volReadout
                            anchors.right: parent.right
                            anchors.verticalCenter: parent.verticalCenter
                            width: 28
                            horizontalAlignment: Text.AlignRight
                            text: Volume.volume.toString()
                            color: Qt.alpha(Theme.fg, 0.6)
                            font.family: Theme.fontFamilyAlt
                            font.pixelSize: 11
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
                                font.family: Theme.fontFamilyDisplay
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

                    // notifications, newest first, in the room the day leaves; they scroll
                    // when there are more. Clear sits in the label row.
                    Item {
                        width: parent.width
                        height: noteLabel.height

                        Text {
                            id: noteLabel
                            text: "Notifications"
                            color: Qt.alpha(Theme.fg, 0.5)
                            font.family: Theme.fontFamilySans
                            font.pixelSize: 10
                        }
                        Text {
                            visible: Notifications.count > 0
                            anchors.right: parent.right
                            text: "Clear"
                            color: Qt.alpha(Theme.fg, clearHit.containsMouse ? 0.9 : 0.5)
                            font.family: Theme.fontFamilySans
                            font.pixelSize: 10

                            MouseArea {
                                id: clearHit
                                anchors.fill: parent
                                anchors.margins: -4
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: Notifications.clearAll()
                            }
                        }
                    }
                    Text {
                        visible: Notifications.count === 0
                        text: "Nothing new"
                        color: Qt.alpha(Theme.fg, 0.4)
                        font.family: Theme.fontFamilySans
                        font.pixelSize: 12
                    }
                    Flickable {
                        id: noteList
                        visible: Notifications.count > 0
                        width: parent.width
                        // down to the panel's bottom margin
                        height: Math.max(0, homeTab.height - 12 - dayColumn.y - y)
                        contentWidth: width
                        contentHeight: noteStack.implicitHeight
                        clip: true
                        boundsBehavior: Flickable.StopAtBounds

                        Column {
                            id: noteStack
                            width: noteList.width
                            spacing: 4

                            Repeater {
                                model: Notifications.notifications.values.slice().reverse()

                                Rectangle {
                                    id: note

                                    required property var modelData

                                    width: noteStack.width
                                    height: 36
                                    radius: 10
                                    color: Qt.alpha(Theme.fg, 0.06)

                                    HoverHandler { id: noteHover }

                                    // the bar is red for critical, the accent otherwise
                                    Rectangle {
                                        x: 8
                                        anchors.verticalCenter: parent.verticalCenter
                                        width: 3
                                        height: 20
                                        radius: 2
                                        color: note.modelData.urgency === NotificationUrgency.Critical
                                            ? Theme.red : Theme.accent
                                    }
                                    Column {
                                        anchors.verticalCenter: parent.verticalCenter
                                        anchors.left: parent.left
                                        anchors.right: parent.right
                                        anchors.leftMargin: 20
                                        anchors.rightMargin: 34
                                        spacing: 1

                                        Text {
                                            width: parent.width
                                            text: note.modelData.summary
                                            color: Theme.fg
                                            textFormat: Text.PlainText
                                            font.family: Theme.fontFamilySans
                                            font.pixelSize: 12
                                            font.weight: Font.DemiBold
                                            elide: Text.ElideRight
                                        }
                                        Text {
                                            width: parent.width
                                            // one line: the body if there is one, else the sender
                                            text: note.modelData.body !== ""
                                                ? note.modelData.body.replace(/\s+/g, " ")
                                                : note.modelData.appName
                                            color: Qt.alpha(Theme.fg, 0.6)
                                            textFormat: Text.PlainText
                                            font.family: Theme.fontFamilySans
                                            font.pixelSize: 10
                                            elide: Text.ElideRight
                                        }
                                    }
                                    // the time, swapped for a dismiss while the pointer is here;
                                    // no hoverEnabled, so the HoverHandler keeps the hover
                                    Text {
                                        anchors.right: parent.right
                                        anchors.rightMargin: 10
                                        anchors.verticalCenter: parent.verticalCenter
                                        text: noteHover.hovered ? "󰅖" : Notifications.timeOf(note.modelData)
                                        color: Qt.alpha(Theme.fg, noteHover.hovered ? 0.7 : 0.4)
                                        font.family: noteHover.hovered ? Theme.fontFamily : Theme.fontFamilyNum
                                        font.pixelSize: noteHover.hovered ? 13 : 10

                                        MouseArea {
                                            anchors.fill: parent
                                            anchors.margins: -6
                                            cursorShape: Qt.PointingHandCursor
                                            onClicked: note.modelData.dismiss()
                                        }
                                    }
                                }
                            }
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
                            text: "Next"
                            color: Qt.alpha(Theme.fg, 0.5)
                            font.family: Theme.fontFamilySans
                            font.pixelSize: 11
                        }
                        Text {
                            anchors.right: parent.right
                            text: root.leftText
                            color: Qt.alpha(Theme.fg, 0.5)
                            font.family: Theme.fontFamilySans
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
                            // p1, p2 and p3 keep their colours; the rest get one of their own
                            readonly property color tint: modelData.late || modelData.priority === 1 ? Theme.red
                                : modelData.priority === 2 ? Theme.accent
                                : modelData.priority === 3 ? Theme.secondary
                                : root.titleTint(modelData.title)

                            width: dayList.width
                            height: 32

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
                                font.family: Theme.fontFamilySans
                                font.pixelSize: 12
                                font.weight: dayRowItem.inFocus || dayRowItem.isNow ? Font.DemiBold : Font.Normal
                                elide: Text.ElideRight
                            }
                            Text {
                                id: whenLabel
                                anchors.verticalCenter: parent.verticalCenter
                                anchors.right: tick.left
                                anchors.rightMargin: 6
                                text: {
                                    const spent = rowSpentMin(dayRowItem.modelData)
                                    const planned = dayRowItem.modelData.task && dayRowItem.modelData.task.estimate > 0 
                                        ? dayRowItem.modelData.task.estimate 
                                        : Schedule.minutesFor(dayRowItem.modelData.title)

                                    // If time spent > 0 or there's an active run, show spent / planned
                                    if (spent > 0 || planned > 0) {
                                        return (spent > 0 ? fmtMin(Math.floor(spent)) : "0m") + (planned > 0 ? " / " + fmtMin(planned) : "")
                                    }
                                    return root.whenText(dayRowItem.modelData)
                                }
                                color: dayRowItem.modelData.late ? Theme.red : Qt.alpha(Theme.fg, 0.5)
                                font.family: Theme.fontFamilyNum
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
                                opacity: rowHover.hovered && root.rowClearable(dayRowItem.modelData) ? 1 : 0
                                color: tickMouse.containsMouse ? Theme.accent : Qt.alpha(Theme.fg, 0.7)
                                font.family: Theme.fontFamily
                                font.pixelSize: Theme.iconSize
                                Behavior on opacity { NumberAnimation { duration: 120 } }

                                MouseArea {
                                    id: tickMouse
                                    anchors.fill: parent
                                    anchors.margins: -5
                                    enabled: rowHover.hovered && root.rowClearable(dayRowItem.modelData)
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
                        font.family: Theme.fontFamilySans
                        font.pixelSize: 12
                    }

                    // adds a task to today, typed in todo.md's own syntax: Call mom @16:30 =45m p2
                    Rectangle {
                        id: addRow
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.bottom: parent.bottom
                        height: 30
                        radius: 8
                        color: input.activeFocus ? Qt.alpha(Theme.fg, 0.08) : "transparent"
                        Behavior on color { ColorAnimation { duration: 120 } }

                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.IBeamCursor
                            onClicked: input.forceActiveFocus()
                        }

                        // the plus sits under the row dots
                        Text {
                            id: plus
                            anchors.verticalCenter: parent.verticalCenter
                            anchors.left: parent.left
                            anchors.leftMargin: 8
                            width: 16
                            horizontalAlignment: Text.AlignHCenter
                            text: "󰐕"
                            color: Qt.alpha(Theme.fg, 0.5)
                            font.family: Theme.fontFamily
                            font.pixelSize: 14
                        }
                        TextInput {
                            id: input
                            anchors.verticalCenter: parent.verticalCenter
                            anchors.left: plus.right
                            anchors.leftMargin: 12
                            anchors.right: parent.right
                            anchors.rightMargin: 10
                            clip: true
                            selectByMouse: true
                            color: Theme.fg
                            selectionColor: Theme.accent
                            selectedTextColor: Theme.bg
                            font.family: Theme.fontFamilySans
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
                                text: "Add a task"
                                color: Qt.alpha(Theme.fg, 0.4)
                                font: input.font
                            }
                        }
                        // the syntax, faint, while the box is empty
                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            anchors.right: parent.right
                            anchors.rightMargin: 10
                            visible: input.text === ""
                            text: "@16:30  =45m  p2"
                            color: Qt.alpha(Theme.fg, 0.3)
                            font.family: Theme.fontFamilyNum
                            font.pixelSize: 11
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
                                    font.family: Theme.fontFamilyDisplay
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
                            visible: root.focusClearable
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
                                    text: {
                                        let p = trackedRow.modelData.planned
                                        if (p <= 0) {
                                            // Look up the task in root.rows to grab its =estimate
                                            const match = root.rows.find(r => r.title === trackedRow.modelData.title)
                                            if (match && match.task && match.task.estimate > 0)
                                                p = match.task.estimate
                                        }
                                        return root.fmtMin(trackedRow.modelData.spent) + (p > 0 ? " / " + root.fmtMin(p) : "")
                                    }
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

            // ── Ports: what is listening, and what the network can reach ───
            Item {
                id: portsTab
                visible: root.tab === "ports"
                y: 46
                width: panel.width
                height: panel.height - y

                // the headline: how many, and how many are open to the network
                Item {
                    id: portsHead
                    x: 18
                    width: panel.width - 36
                    height: 38

                    Column {
                        spacing: 2

                        Text {
                            text: Ports.ports.length + " listening"
                            color: Theme.fg
                            font.family: Theme.fontFamilySans
                            font.pixelSize: 15
                            font.weight: Font.DemiBold
                        }
                        Text {
                            text: Ports.exposedCount > 0 ? Ports.exposedCount + " open to the network"
                                                         : "None reachable from the network"
                            color: Ports.exposedCount > 0 ? Theme.red : Theme.green
                            font.family: Theme.fontFamilySans
                            font.pixelSize: 11
                        }
                    }
                    Text {
                        anchors.right: parent.right
                        text: Ports.note !== "" ? Ports.note : Ports.loaded ? "" : "looking…"
                        color: Ports.note !== "" ? Theme.green : Qt.alpha(Theme.fg, 0.4)
                        font.family: Theme.fontFamilySans
                        font.pixelSize: 11
                    }
                }

                // a click copies the address; the buttons on a hovered row open it or close its process
                ListView {
                    id: portsList
                    x: 12
                    y: portsHead.height + 6
                    width: panel.width - 30
                    height: parent.height - y - 12
                    clip: true
                    boundsBehavior: Flickable.StopAtBounds
                    model: Ports.ports

                    delegate: Item {
                        id: portRow
                        required property var modelData
                        // waiting for the second tap that closes its process
                        readonly property bool armed: Ports.armed === modelData.key

                        width: portsList.width
                        height: 34

                        HoverHandler { id: portHover }

                        Rectangle {
                            anchors.fill: parent
                            anchors.topMargin: 1
                            anchors.bottomMargin: 1
                            radius: 8
                            color: portRow.armed ? Qt.alpha(Theme.red, 0.16)
                                 : portHover.hovered ? Qt.alpha(Theme.fg, 0.06) : "transparent"
                            Behavior on color { ColorAnimation { duration: 120 } }
                        }
                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onClicked: Ports.copy(portRow.modelData)
                        }

                        // red when the network can reach it, grey when only this machine can
                        Rectangle {
                            id: portDot
                            anchors.verticalCenter: parent.verticalCenter
                            x: 10
                            width: 8
                            height: 8
                            radius: 4
                            color: portRow.modelData.exposed ? Theme.red : Qt.alpha(Theme.fg, 0.25)
                        }
                        Text {
                            id: portNumber
                            anchors.verticalCenter: parent.verticalCenter
                            x: 28
                            width: 56
                            text: ":" + portRow.modelData.port
                            color: Theme.fg
                            font.family: Theme.fontFamilyNum
                            font.pixelSize: 13
                            font.bold: true
                        }
                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            anchors.left: portNumber.right
                            anchors.right: portConns.visible ? portConns.left : portDetail.left
                            anchors.rightMargin: 10
                            text: portRow.modelData.process !== "" ? portRow.modelData.process : "unknown owner"
                            color: portRow.modelData.process !== "" ? Theme.fg : Qt.alpha(Theme.fg, 0.4)
                            font.family: Theme.fontFamilySans
                            font.pixelSize: 12
                            elide: Text.ElideRight
                        }
                        // live connections to it: what turns "open" into "in use"
                        Rectangle {
                            id: portConns
                            visible: portRow.modelData.conns > 0
                            anchors.verticalCenter: parent.verticalCenter
                            anchors.right: portDetail.left
                            anchors.rightMargin: 8
                            width: connCount.implicitWidth + 12
                            height: 20
                            radius: 10
                            color: Qt.alpha(Theme.fg, 0.1)

                            Text {
                                id: connCount
                                anchors.centerIn: parent
                                text: portRow.modelData.conns
                                color: Theme.fg
                                font.family: Theme.fontFamilyNum
                                font.pixelSize: 11
                            }
                        }
                        Text {
                            id: portDetail
                            anchors.verticalCenter: parent.verticalCenter
                            anchors.right: portActions.left
                            anchors.rightMargin: 8
                            // armed, the detail stops describing and asks
                            text: portRow.armed ? "press again to close  ·  pid " + portRow.modelData.pid
                                : portRow.modelData.proto
                                  + (portRow.modelData.pid > 0 ? "  ·  pid " + portRow.modelData.pid : "")
                                  + (portRow.modelData.exposed ? "  ·  " + portRow.modelData.host : "")
                            color: portRow.armed ? Theme.red : Qt.alpha(Theme.fg, 0.5)
                            font.family: Theme.fontFamilyNum
                            font.pixelSize: 10
                        }
                        // open and close, only under the pointer (or armed): fixed buttons on every
                        // row would be noise. Without a pid there is nothing to close.
                        Row {
                            id: portActions
                            anchors.verticalCenter: parent.verticalCenter
                            anchors.right: parent.right
                            anchors.rightMargin: 8
                            spacing: 4
                            opacity: portHover.hovered || portRow.armed ? 1 : 0
                            Behavior on opacity { NumberAnimation { duration: 120 } }

                            IconButton {
                                width: 26
                                height: 26
                                visible: Ports.isWeb(portRow.modelData) && !portRow.armed
                                enabled: portActions.opacity > 0
                                glyph: "󰏌"
                                onClicked: Ports.openWeb(portRow.modelData)
                            }
                            IconButton {
                                width: 26
                                height: 26
                                visible: portRow.modelData.pid > 0
                                enabled: portActions.opacity > 0
                                danger: portRow.armed
                                glyph: "󰙦"
                                onClicked: portRow.armed ? Ports.close(portRow.modelData) : Ports.arm(portRow.modelData)
                            }
                        }
                    }
                }

                Text {
                    visible: Ports.loaded && Ports.ports.length === 0
                    y: portsHead.height + 14
                    x: 18
                    text: "Nothing is listening, or ss is not installed"
                    color: Qt.alpha(Theme.fg, 0.5)
                    font.family: Theme.fontFamilySans
                    font.pixelSize: 12
                }
            }

            // ── Usage: time per app, from the usage data ───────────────────
            UsagePage {
                visible: root.tab === "usage"
                y: 40
                width: panel.width
                height: panel.height - y
            }

            // ── Share: the files queued for a LocalSend send ───────────────
            SharePage {
                visible: root.tab === "share"
                y: 40
                width: panel.width
                height: panel.height - y
            }

            // ── Buds: the battery of the Galaxy Buds ───────────────────────
            BudsPage {
                visible: root.tab === "buds"
                y: 40
                width: panel.width
                height: panel.height - y
            }

            // ── Tray: favourite files, a carousel to open them from ───────
            TrayPage {
                id: trayPage
                visible: root.tab === "tray"
                y: 40
                width: panel.width
                height: panel.height - y
            }

            // ── Week: the schedule's grid ──────────────────────────────────
            WeekGrid {
                visible: root.tab === "week"
                x: 12
                y: 72
                width: panel.width - 24
                height: panel.height - y - 10
            }

            // ── Control: the switches and sliders, from the gear ───────────
            // centred under the header; taller than the panel, the card's clip does the rest
            ControlPage {
                id: controlPage
                visible: root.onControl
                x: (panel.width - width) / 2
                // 12 px under the header
                y: 50
            }
        }
    }

    // the strip's clock fades in on open and out on close
    property real clockShown: 0
    NumberAnimation {
        id: fadeIn
        target: root
        property: "clockShown"
        to: 1
        duration: 150
        easing.type: Easing.OutCubic
    }
    NumberAnimation {
        id: fadeOut
        target: root
        property: "clockShown"
        to: 0
        duration: 150
        easing.type: Easing.OutCubic
    }
}
