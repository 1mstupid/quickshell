pragma Singleton

import Quickshell
import Quickshell.Io
import Quickshell.Services.Notifications
import QtQuick
import "NotificationMeta.js" as Meta

// Notifications. A notification is kept until it is dismissed; its toast is a
// shorter life. A toast ends when it times out, and the notification stays in
// the history, the notch the bar's bell opens. While `muted`, new notifications
// skip the toast and go straight to the history.
Singleton {
    id: root

    // everything not dismissed, oldest first
    property var notifications: server.trackedNotifications

    // how many are kept; the oldest are dismissed first
    readonly property int maxKept: 50

    // do not disturb: no toasts, except for critical notifications
    property bool muted: false
    // whether the history notch is open
    property bool open: false

    // { time, quiet } by notification id, see NotificationMeta.js
    property var meta: ({})

    readonly property int count: server.trackedNotifications.values.length
    readonly property int toastCount: server.trackedNotifications.values.filter(n => isToast(n)).length

    function isToast(n) { return Meta.isToast(meta, n.id) }
    function timeOf(n) { return Meta.timeOf(meta, n.id) }
    function expire(n) { meta = Meta.expired(meta, n.id) }
    function toggleHistory() { open = !open }

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

            // nothing times out of the history, so cap it
            const all = server.trackedNotifications.values
            const extra = all.length - root.maxKept
            if (extra > 0)
                all.slice(0, extra).forEach(x => x.dismiss())
        }
    }

    // qs ipc call notifications toggle | toggleMute | clear
    IpcHandler {
        target: "notifications"
        function toggle(): void { root.toggleHistory() }
        function toggleMute(): void { root.muted = !root.muted }
        function clear(): void { root.clearAll() }
    }
}
