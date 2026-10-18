//@ pragma UseQApplication

import Quickshell
import Quickshell.Wayland
import Quickshell.Io
import QtQuick
import "./widgets/player"
import "./widgets/app_launcher"
import "./widgets/network"
import "./widgets/power_menu"

ShellRoot {

    NotificationToast {}

    WallpaperPicker {}

    VolumeOsd {}

    Variants {
        model: Quickshell.screens

        Bar {}
    }
    Variants {
        model: Quickshell.screens
        AppLauncher {
            property var modelData
            screen: modelData
        }
    }
    Variants {
        model: Quickshell.screens
        PowerMenu {
            property var modelData
            screen: modelData
        }
    }
    Variants {
        model: Quickshell.screens

        Network {
            property var modelData
            screen: modelData
        }
    }

    property var notifications: Notifications.notifications
}
