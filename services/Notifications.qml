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
            console.log("GOT:", n.summary, "|", n.body)
            n.tracked = true
        }
    }

    function clearAll() {
        for (const n of server.trackedNotifications)
            n.dismiss()
    }
}
