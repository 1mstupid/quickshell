import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland

PanelWindow {
    id: root

    visible: false

    anchors {
        top: true
        bottom: true
        left: true
        right: true
    }

    color: "transparent"

    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: root.visible ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None
    WlrLayershell.namespace: "quickshell-wallpapers"

    property int cardPadding: 20
    property int cardWidth: 548
    property int cardHeight: 308 // Increased size (maintaining 16:9 ratio)

    property var wallpapers: []
    property string applyingPath: ""
    property bool randomPending: false

    onVisibleChanged: {
        if (visible) {
            lister.running = true
            overlay.forceActiveFocus()
        }
    }

    function toggle() { visible = !visible }

    function applyRandom() {
        randomPending = true
        lister.running = true
    }

    function apply(path) {
        applyingPath = path
        if (!visible)
            visible = true 
        canvas.loadImage("file://" + path)
    }

    // Quickshell IPC Handler
    IpcHandler {
        target: "wallpapers"
        function toggle(): void { root.toggle() }
        function random(): void { root.applyRandom() }
        function set(path: string): void { root.apply(path) }
    }

    property var _found: []
    Process {
        id: lister
        command: ["sh", "-c",
            "find -L \"" + Theme.configDir + "/../.local/share/wallpapers\" -maxdepth 1 -type f " +
            "\\( -iname '*.png' -o -iname '*.jpg' -o -iname '*.jpeg' \\) | sort"]
        stdout: SplitParser {
            onRead: line => { if (line.trim() !== "") root._found.push(line.trim()) }
        }
        onRunningChanged: {
            if (running) {
                root._found = []
            } else {
                root.wallpapers = root._found
                if (root.randomPending) {
                    root.randomPending = false
                    if (root.wallpapers.length > 0)
                        root.apply(root.wallpapers[
                            Math.floor(Math.random() * root.wallpapers.length)])
                }
            }
        }
    }

    // Background overlay with 0.8 opacity (clicking outside dismisses)
    Rectangle {
        id: overlay

        anchors.fill: parent
        anchors.topMargin: 300
        anchors.bottomMargin: 300
        color: Qt.rgba(0, 0, 0, 0.8)
        focus: true

        // Keyboard & Vim Navigation
        Keys.onPressed: event => {
            if (event.key === Qt.Key_Escape) {
                root.visible = false
                event.accepted = true
            } else if (event.key === Qt.Key_Left || event.text === "h") {
                if (carousel.currentIndex > 0)
                    carousel.currentIndex--
                event.accepted = true
            } else if (event.key === Qt.Key_Right || event.text === "l") {
                if (carousel.currentIndex < carousel.count - 1)
                    carousel.currentIndex++
                event.accepted = true
            } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                if (carousel.currentIndex >= 0 && root.wallpapers.length > 0) {
                    root.apply(root.wallpapers[carousel.currentIndex])
                }
                event.accepted = true
            }
        }

        MouseArea {
            anchors.fill: parent
            onClicked: root.visible = false
        }

        Canvas {
            id: canvas
            x: 200; y: 30
            width: 100
            height: 50
            visible: false

            onImageLoaded: {
                const url = "file://" + root.applyingPath
                if (root.applyingPath !== "" && isImageError(url))
                    root.applyingPath = ""
                else
                    requestPaint()
            }

            onPaint: {
                if (root.applyingPath === "")
                    return
                const url = "file://" + root.applyingPath
                if (!isImageLoaded(url))
                    return
                const ctx = getContext("2d")
                ctx.clearRect(0, 0, width, height)
                ctx.drawImage(url, 0, 0, width, height)
                const data = ctx.getImageData(0, 0, width, height).data
                unloadImage(url) 
                root.finish(data)
            }
        }

        Item {
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            height: root.cardHeight + root.cardPadding * 2

            ListView {
                id: carousel
                anchors.fill: parent
                orientation: ListView.Horizontal
                spacing: 24
                clip: true
                model: root.wallpapers

                snapMode: ListView.SnapToItem
                preferredHighlightBegin: width / 2 - root.cardWidth / 2
                preferredHighlightEnd: width / 2 + root.cardWidth / 2
                highlightRangeMode: ListView.StrictlyEnforceRange
                highlightMoveDuration: 100 // Faster transition when pressing keys (default is -1)
                flickDeceleration: 3000

                delegate: Item {
                    id: cell
                    required property int index 
                    required property string modelData
                    readonly property bool busy: root.applyingPath === modelData
                    
                    width: root.cardWidth
                    height: root.cardHeight
                    anchors.verticalCenter: parent.verticalCenter

                    Rectangle {
                        anchors.fill: parent
                        radius: 12
                        color: Qt.alpha(Theme.fg, 0.06)
                        
                        scale: mouse.containsMouse || carousel.currentIndex === index ? 1.05 : 1.0
                        Behavior on scale { 
                            NumberAnimation { 
                                duration: 10 
                                easing.type: Easing.OutCubic 
                            } 
                        }
                        Image {
                            anchors.fill: parent
                            anchors.margins: 2
                            source: "file://" + cell.modelData
                            sourceSize.width: root.cardWidth * 2
                            fillMode: Image.PreserveAspectCrop
                            asynchronous: true
                            clip: true
                            layer.enabled: true
                        }

                        Rectangle {
                            anchors.fill: parent
                            radius: 12
                            color: "transparent"
                            border.width: cell.busy ? 3 : (mouse.containsMouse || carousel.currentIndex === index) ? 2 : 0
                            border.color: cell.busy ? Theme.accent : Qt.alpha(Theme.accent, 0.8)

                            SequentialAnimation on opacity {
                                running: cell.busy
                                loops: Animation.Infinite
                                alwaysRunToEnd: true
                                NumberAnimation { to: 0.4; duration: 120 } // Reduced from 350
                                NumberAnimation { to: 1.0; duration: 120 } // Reduced from 350
                            }
                        }

                        MouseArea {
                            id: mouse
                            anchors.fill: parent
                            hoverEnabled: true
                            onClicked: {
                                carousel.currentIndex = index
                                root.apply(cell.modelData)
                            }
                        }
                    }
                }
            }
        }
    }

    // --- palette math ---

    function rgbToHsl(r, g, b) {
        const mx = Math.max(r, g, b), mn = Math.min(r, g, b)
        const l = (mx + mn) / 2
        if (mx === mn)
            return [0, 0, l]
        const d = mx - mn
        const s = l > 0.5 ? d / (2 - mx - mn) : d / (mx + mn)
        let h
        if (mx === r) h = ((g - b) / d + (g < b ? 6 : 0))
        else if (mx === g) h = (b - r) / d + 2
        else h = (r - g) / d + 4
        return [h * 60, s, l]
    }

    function hslToHex(h, s, l) {
        h = ((h % 360) + 360) % 360
        const c = (1 - Math.abs(2 * l - 1)) * s
        const x = c * (1 - Math.abs((h / 60) % 2 - 1))
        const m = l - c / 2
        let r, g, b
        if (h < 60) { r = c; g = x; b = 0 }
        else if (h < 120) { r = x; g = c; b = 0 }
        else if (h < 180) { r = 0; g = c; b = x }
        else if (h < 240) { r = 0; g = x; b = c }
        else if (h < 300) { r = x; g = 0; b = c }
        else { r = c; g = 0; b = x }
        const to = v => Math.round((v + m) * 255).toString(16).padStart(2, "0")
        return "#" + to(r) + to(g) + to(b)
    }

    function hueDist(a, b) {
        const d = Math.abs(a - b) % 360
        return d > 180 ? 360 - d : d
    }

    function luminance(hex) {
        const c = [1, 3, 5].map(i => parseInt(hex.slice(i, i + 2), 16) / 255)
            .map(v => v <= 0.03928 ? v / 12.92 : Math.pow((v + 0.055) / 1.055, 2.4))
        return 0.2126 * c[0] + 0.7152 * c[1] + 0.0722 * c[2]
    }

    function contrast(a, b) {
        const x = luminance(a), y = luminance(b)
        return (Math.max(x, y) + 0.05) / (Math.min(x, y) + 0.05)
    }

    function legible(h, s, l, bg, min) {
        let hex = hslToHex(h, s, l)
        while (contrast(hex, bg) < min && l < 0.9) {
            l += 0.02
            hex = hslToHex(h, s, l)
        }
        return hex
    }

    function finish(d) {
        const bins = new Map()
        let total = 0
        for (let i = 0; i < d.length; i += 4) {
            if (d[i + 3] < 200)
                continue
            total++
            const key = (d[i] >> 4 << 8) | (d[i + 1] >> 4 << 4) | (d[i + 2] >> 4)
            let e = bins.get(key)
            if (!e) bins.set(key, e = [0, 0, 0, 0])
            e[0]++; e[1] += d[i]; e[2] += d[i + 1]; e[3] += d[i + 2]
        }
        if (total === 0)
            return
        const clusters = [...bins.values()].map(e => {
            const [h, s, l] = rgbToHsl(e[1] / e[0] / 255, e[2] / e[0] / 255, e[3] / e[0] / 255)
            return { n: e[0], h, s, l }
        }).sort((a, b) => b.n - a.n).slice(0, 40)

        const art = clusters.slice(0, 8).reduce((s, c) => s + c.n, 0) / total > 0.85

        let bgC = clusters[0]
        let best = -1
        for (const c of clusters) {
            const score = c.n * (1.15 - c.l)
            if (score > best) { best = score; bgC = c }
        }
        const bgH = bgC.h, bgS = Math.min(bgC.s, art ? 0.35 : 0.26)
        const bgL = art ? Math.min(Math.max(bgC.l, 0.09), 0.2)
                        : Math.min(Math.max(bgC.l * 0.7, 0.1), 0.17)

        let bea = null
        {
            const cand = []
            for (const e of bins.values()) {
                const [h, s, l] = rgbToHsl(e[1] / e[0] / 255, e[2] / e[0] / 255, e[3] / e[0] / 255)
                if (s >= 0.15 && l >= bgC.l + 0.3 && hueDist(h, bgH) >= 50)
                    cand.push({ n: e[0], h, s, l })
            }
            if (cand.length) {
                const seed = cand.reduce((a, c) => c.l * c.n > a.l * a.n ? c : a)
                let n = 0, ss = 0, ls = 0
                for (const c of cand)
                    if (hueDist(c.h, seed.h) <= 30) { n += c.n; ss += c.s * c.n; ls += c.l * c.n }
                if (n / total >= 0.0005 && n / total <= 0.02)
                    bea = { n, h: seed.h, s: Math.max(ss / n, 0.45), l: ls / n }
            }
        }

        let priC = bea
        best = 0
        if (!priC)
            for (const c of clusters) {
                const mid = (c.l > 0.15 && c.l < 0.85) ? 1 : 0.2
                const score = Math.pow(c.s, 1.5) * Math.sqrt(c.n / total) * mid
                if (c.s > 0.15 && score > best) { best = score; priC = c }
            }
        const priH = priC ? priC.h : bgH
        const priS = priC ? (art ? Math.min(Math.max(priC.s, 0.3), 0.85)
                                   : Math.min(Math.max(priC.s, 0.3), 0.55)) : 0.15
        const priL = priC ? (art ? Math.min(Math.max(priC.l, 0.45), 0.75)
                                   : Math.min(Math.max(priC.l, 0.62), 0.78)) : 0.7

        let secC = null
        best = 0
        for (const c of clusters) {
            if (c.s < 0.2 || hueDist(c.h, priH) < 45)
                continue
            const score = c.s * Math.sqrt(c.n / total)
            if (score > best) { best = score; secC = c }
        }
        const secH = secC ? secC.h : priH + 35
        const secS = secC ? (art ? Math.min(Math.max(secC.s, 0.25), 0.75)
                                   : Math.min(Math.max(secC.s, 0.2), 0.4)) : priS * 0.7
        const secL = secC ? (art ? Math.min(Math.max(secC.l, 0.45), 0.8)
                                   : Math.min(Math.max(secC.l, 0.7), 0.8)) : 0.74

        let alC = null
        for (const c of clusters) {
            if ((c.h <= 20 || c.h >= 340) && c.s > 0.35 && (!alC || c.n > alC.n))
                alC = c
        }
        const alHsl = alC ? (art ? [alC.h, Math.min(Math.max(alC.s, 0.4), 0.8),
                                      Math.min(Math.max(alC.l, 0.5), 0.65)]
                                 : [alC.h, Math.min(Math.max(alC.s, 0.35), 0.45), 0.66])
                          : [4, 0.4, 0.66]

        let fgH = 42
        for (const c of clusters) {
            if (c.h >= 20 && c.h <= 60 && c.l > 0.3) { fgH = c.h; break }
        }

        const bg = hslToHex(bgH, bgS, bgL)
        const palette = [
            bg,
            hslToHex(bgH, bgS, bgL + 0.06),
            hslToHex(fgH, 0.2, 0.78),
            hslToHex(priH, 0.18, bgL + 0.1),
            legible(priH, priS, priL, bg, 4.5),
            legible(secH, secS, secL, bg, 4.5),
            legible(alHsl[0], alHsl[1], alHsl[2], bg, 4.5),
            legible(bgH, 0.1, 0.4, bg, 3.0)
        ]

        const terms = new Array(6)
        terms[0] = alC ? alC : { h: 4, s: 0.4, l: 0.66 }
        const anchors = [[1, 120], [2, 55], [3, 225], [4, 300], [5, 180]]
        const cands = clusters
            .filter(c => c.s > 0.2 && c.l > 0.15 && c.l < 0.85
                && hueDist(c.h, terms[0].h) >= 30)
            .sort((a, b) => b.s * Math.sqrt(b.n) - a.s * Math.sqrt(a.n))
            .slice(0, 8)
        for (let pass = 0; pass < anchors.length; pass++) {
            let bi = -1, bc = -1, bd = 46
            for (const [i, a] of anchors) {
                if (terms[i]) continue
                for (let j = 0; j < cands.length; j++)
                    if (cands[j] && hueDist(cands[j].h, a) < bd) {
                        bd = hueDist(cands[j].h, a); bi = i; bc = j
                    }
            }
            if (bi < 0) break
            terms[bi] = cands[bc]; cands[bc] = null
        }
        for (const [i, a] of anchors)
            if (!terms[i]) terms[i] = { h: a, s: art ? 0.5 : 0.4, l: 0.62 }

        const ansi = new Array(16)
        ansi[0] = hslToHex(bgH, bgS, bgL + 0.06)
        ansi[7] = hslToHex(fgH, 0.15, 0.72)
        ansi[8] = hslToHex(bgH, 0.1, 0.38)
        ansi[15] = hslToHex(fgH, 0.18, 0.86)
        for (let i = 0; i < 6; i++) {
            const t = terms[i]
            const s = art ? Math.min(Math.max(t.s, 0.35), 0.8) : 0.4
            const l = art ? Math.min(Math.max(t.l, 0.5), 0.7) : 0.66
            ansi[i + 1] = legible(t.h, s, l, bg, 4.0)
            ansi[i + 9] = legible(t.h, art ? s : 0.42, Math.min(l + 0.08, 0.78), bg, 4.0)
        }

        Quickshell.execDetached(
            ["wallpaper-theme", root.applyingPath]
                .concat(palette).concat(ansi))
        root.applyingPath = ""
        root.visible = false
    }
}
