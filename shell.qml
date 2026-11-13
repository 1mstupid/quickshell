//@ pragma UseQApplication

import Quickshell
import Quickshell.Wayland
import Quickshell.Io
import QtQuick
import "./services"
import "./widgets/app_launcher"
import "./widgets/bar"
import "./widgets/bar/media"
import "./widgets/dashboard"
import "./widgets/drawer"
import "./widgets/focus_notch"
import "./widgets/border"
import "./widgets/habits"
import "./widgets/layout"
import "./widgets/power_menu"
import "./widgets/todo"
import "./widgets/usage"
import "./widgets/wallpaper"
import "./widgets/colorscheme"

ShellRoot {

    ControlDrawer {}

    WallpaperPicker {}
    ColorschemePicker {}

    AppLauncher {}

    PowerMenu {}

    Dashboard {}

    FocusNotch {}

    MediaWidget {}

    Usage {}

    FocusWidget {}

    TodoWidget {}

    HabitsWidget {}

    LayoutEditor {}

    Variants {
        model: Quickshell.screens

        Bar {}
    }
    Variants {
        model: Quickshell.screens

        ScreenBorder {}
    }

    property var notifications: Notifications.notifications
    // referenced so the singleton starts with the shell
    property var sleepReminder: SleepReminder
}
