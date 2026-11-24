pragma Singleton
import QtQuick
import Quickshell

// Sound effects, played from the files in assets/. Nothing plays unless the
// sounds setting is on. Each play is one paplay process, as the Pomodoro alarm
// is, so there is nothing to keep loaded or to stop.
Singleton {
    id: root

    // paplay's volume: 65536 is full, and the alarm uses 40000 too
    readonly property int volume: 40000

    // the name a caller passes, and the file it plays (relative to the shell folder)
    readonly property var files: ({
        open: "assets/reusables/dropdown/list.wav",
        close: "assets/network/silk_retract.wav",
        "open-wallpaper": "assets/musicpopup/swoosh.wav",
        "close-wallpaper": "assets/guide/barconfig/out.wav",
        "open-colors": "assets/reusables/iconbutton/click.wav",
        "close-colors": "assets/guide/barconfig/in.wav",
        "open-settings": "assets/network/connect.wav",
        "close-settings": "assets/reusables/clickbutton/click2.wav",
        "open-power": "assets/network/bh_power_on_burst.wav",
        "close-power": "assets/network/bh_power_off_implode.wav",
        "open-notch": "assets/network/bh_orb_pop.wav",
        "close-notch": "assets/reusables/dropdown/click.wav",
        page: "assets/network/tick-1.wav",
        toggle: "assets/reusables/switch/sfx.wav",
        slide: "assets/network/tick-2.wav",
        launch: "assets/network/switch.wav",
        apply: "assets/system/quick_click.wav",
        notify: "assets/notifications/Progress.wav",
        done: "assets/reusables/clickbutton/click.wav"
    })

    function play(name) {
        const f = files[name]
        if (!UserSettings.sounds || f === undefined)
            return
        Quickshell.execDetached(["paplay", "--volume=" + volume, Quickshell.shellDir + "/" + f])
    }
}
