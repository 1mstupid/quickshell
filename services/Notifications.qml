pragma Singleton

import Quickshell
import Quickshell.Services.Notifications
import QtQuick

Singleton {
    id: root

    property var notifications: server.trackedNotifications

    NotificationServer {
        id: server

        actionsSupported: true
        bodySupported: true
        imageSupported: true

        onNotification: n => {
            n.tracked = true
        }
    }

    function clearAll() {
        const list = server.trackedNotifications.values.slice()
        for (const n of list)
            n.dismiss()
    }
}
