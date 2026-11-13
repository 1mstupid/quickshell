pragma Singleton

import Quickshell
import Quickshell.Io
import Quickshell.Services.Notifications
import QtQuick
import "NotificationMeta.js" as Meta

// Notifications. A notification is kept until it is dismissed; its toast is a
// shorter life: a glyph with a draining ring on the bar's pill. The toast ends when
// it times out, and the notification stays in the list on the focus notch's Home
// page. While `muted`, new notifications skip the toast and go straight to that list.
Singleton {
    id: root

    // everything not dismissed, oldest first
    property var notifications: server.trackedNotifications

    // how many are kept; the oldest are dismissed first
    readonly property int maxKept: 50

    // do not disturb: no toasts, except for critical notifications
    property bool muted: false

    // how long the glyph stays after the last notification arrived
    readonly property int toastLifetime: 5000
    // counts the notifications that got a toast, so the glyph's ring knows when to start over
    property int arrivals: 0

    // { time, quiet } by notification id, see NotificationMeta.js
    property var meta: ({})

    readonly property int count: server.trackedNotifications.values.length
    readonly property int toastCount: server.trackedNotifications.values.filter(n => isToast(n)).length

    function isToast(n) { return Meta.isToast(meta, n.id) }
    function timeOf(n) { return Meta.timeOf(meta, n.id) }
    function expire(n) { meta = Meta.expired(meta, n.id) }

    // a critical notification keeps its toast until it is dismissed or seen
    readonly property bool critical: server.trackedNotifications.values
        .some(n => isToast(n) && n.urgency === NotificationUrgency.Critical)

    // ends the toasts; critical ones only when `includeCritical`, as they never time out
    function endToasts(includeCritical) {
        for (const n of server.trackedNotifications.values.slice())
            if (isToast(n) && (includeCritical || n.urgency !== NotificationUrgency.Critical))
                expire(n)
    }

    // one timer for all the toasts: each arrival starts it over, as it does the ring
    Timer {
        id: toastTimer
        interval: root.toastLifetime
        onTriggered: root.endToasts(false)
    }

    function clearAll() {
        const list = server.trackedNotifications.values.slice()
        for (const n of list)
            n.dismiss()
    }

    NotificationServer {
        id: server

        actionsSupported: true
        bodySupported: true
        imageSupported: true

        onNotification: n => {
            // decided before tracking, so a muted notification never flashes a toast
            const quiet = root.muted && n.urgency !== NotificationUrgency.Critical
            const live = server.trackedNotifications.values.map(x => x.id)
            root.meta = Meta.arrived(root.meta, live, n.id, Qt.formatTime(new Date(), "hh:mm"), quiet)
            n.tracked = true
            AppUsage.countNotification()
            if (!quiet) {
                root.arrivals++
                toastTimer.restart()
            }

            // nothing times out of the list, so cap it
            const all = server.trackedNotifications.values
            const extra = all.length - root.maxKept
            if (extra > 0)
                all.slice(0, extra).forEach(x => x.dismiss())
        }
    }

    // qs ipc call notifications toggle | toggleMute | clear
    IpcHandler {
        target: "notifications"
        // opens the focus notch on Home, where the list now lives
        function toggle(): void { FocusNotchState.toggleHome() }
        function toggleMute(): void { root.muted = !root.muted }
        function clear(): void { root.clearAll() }
    }
}
