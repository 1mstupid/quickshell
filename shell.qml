//@ pragma UseQApplication

import Quickshell
import Quickshell.Wayland
import Quickshell.Io
import QtQuick
import "./services"
import "./widgets/app_launcher"
import "./widgets/bar"
import "./widgets/bar/media"
import "./widgets/focus_notch"
import "./widgets/border"
import "./widgets/notify"
import "./widgets/habits"
import "./widgets/layout"
import "./widgets/lyrics"
import "./widgets/lock"
import "./widgets/power_menu"
import "./widgets/settings"
import "./widgets/study"
import "./widgets/todo"
import "./widgets/usage"
import "./widgets/wallpaper"
import "./widgets/colorscheme"
import "./widgets/share"
import "./widgets/screenshot"

ShellRoot {



    PowerMenu {}

    SharePanel {}

    NotifyStack {}

    SettingsWindow {}


    MediaWidget {}

    LyricsWidget {}

    Usage {}

    FocusWidget {}

    StudyWidget {}

    TodoWidget {}

    HabitsWidget {}

    LayoutEditor {}

    Screenshot {}

    Lock {}

    Variants {
        model: Quickshell.screens

        Bar {}
    }

    property var notifications: Notifications.notifications
    // referenced so the singleton starts with the shell
    property var sleepReminder: SleepReminder
}
