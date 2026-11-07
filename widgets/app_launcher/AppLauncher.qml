import Quickshell
import Quickshell.Wayland
import Quickshell.Io
import QtQuick
import "../../services"
import "../notch"
import "Modes.js" as Modes

// Top-anchored launcher. Grows out of the bar pill, the same way the
// wallpaper picker and clipboard do.
PanelWindow {
    id: root

    screen: PillState.originScreen
    visible: false

    anchors {
        top: true
        left: true
        right: true
    }
    implicitHeight: PillState.pillTop + maxPanelH + 12

    color: "transparent"
    exclusionMode: ExclusionMode.Ignore

    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: root.visible ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None
    WlrLayershell.namespace: "quickshell-launcher"

    IpcHandler {
        target: "applauncher"
        function toggle(): void { AppLauncherState.toggle() }
    }

    // ── Geometry ───────────────────────────────────────────────────────────
    readonly property int maxVisible: 7
    readonly property int itemH: 44
    readonly property int panelW: 400
    // 12 top + 34 search + 8 gap + 8 gap + 16 footer + 12 bottom, plus the rows
    readonly property int chromeH: 90
    readonly property int maxPanelH: chromeH + maxVisible * itemH

    // 0 = the bar pill, 1 = the full panel
    property real t: 0

    // eases when the number of results changes
    property real panelH: chromeH + Math.max(1, Math.min(results.length, maxVisible)) * itemH
    Behavior on panelH {
        NumberAnimation { duration: 250; easing.type: Easing.OutCubic }
    }

    // ── State ──────────────────────────────────────────────────────────────
    property string searchQuery: ""
    property int selectedIndex: 0
    readonly property bool isSearching: searchQuery.trim() !== ""

    // "" is the app list; "calc" etc. come from a bang (Modes.js)
    property string mode: ""
    readonly property var modeInfo: Modes.find(mode)

    // what the list shows, whichever mode: plain objects, so every row looks
    // alike. kind says what Enter does: "app", "mode" or "calc".
    property var results: {
        var q = searchQuery.trim();

        if (mode === "calc") {
            // an answer for an older expression is not shown while typing
            if (Calc.result === "" || Calc.resultFor !== q)
                return [];
            return [{ kind: "calc", title: Calc.result, subtitle: q, icon: "", glyph: modeInfo.glyph, value: Calc.result }];
        }

        // a half-typed bang offers the modes it could become
        var hints = Modes.hints(searchQuery);
        if (hints.length > 0) {
            return hints.map(function (m) {
                return { kind: "mode", title: m.title, subtitle: m.subtitle, icon: "", glyph: m.glyph, value: m.name };
            });
        }

        return appResults(q.toLowerCase());
    }

    onResultsChanged: selectedIndex = 0

    // Search: filter by name / genericName / keywords, alpha sort. No query:
    // recent apps first, then alphabetical.
    function appResults(q) {
        var vals = DesktopEntries.applications.values;
        var list;

        if (q !== "") {
            list = vals.filter(function (e) {
                if (e.name.toLowerCase().indexOf(q) !== -1)
                    return true;
                if (e.genericName && e.genericName.toLowerCase().indexOf(q) !== -1)
                    return true;
                for (var i = 0; i < e.keywords.length; i++)
                    if (e.keywords[i].toLowerCase().indexOf(q) !== -1)
                        return true;
                return false;
            }).sort(function (a, b) {
                return a.name.localeCompare(b.name);
            });
        } else {
            var recent = AppLauncherState.recentIds;
            list = vals.slice().sort(function (a, b) {
                var ai = recent.indexOf(a.id);
                var bi = recent.indexOf(b.id);
                if (ai !== -1 && bi !== -1)
                    return ai - bi;
                if (ai !== -1)
                    return -1;
                if (bi !== -1)
                    return 1;
                return a.name.localeCompare(b.name);
            });
        }

        return list.map(function (e) {
            return { kind: "app", title: e.name, subtitle: subtitleOf(e), icon: e.icon, glyph: "", entry: e };
        });
    }

    readonly property string emptyText: {
        if (mode !== "calc")
            return "No apps found";
        if (searchQuery.trim() === "")
            return "Type an expression";
        return Calc.busy ? "" : "No result";
    }

    // one line of secondary text per app: its generic name, else its category
    function subtitleOf(entry) {
        if (entry.genericName && entry.genericName !== "")
            return entry.genericName;
        if (entry.categories && entry.categories.length > 0)
            return entry.categories[0];
        return "";
    }

    // ── Open / close ───────────────────────────────────────────────────────
    function openLauncher() {
        PillState.owner = "applauncher";
        mode = "";
        searchInput.text = "";
        visible = true;
        morph.stop();
        morph.from = root.t;
        morph.to = 1;
        morph.start();
    }

    function close() {
        morph.stop();
        morph.from = root.t;
        morph.to = 0;
        morph.start();
    }

    NumberAnimation {
        id: morph
        target: root
        property: "t"
        duration: 480
        easing.type: Easing.InOutCubic
        onFinished: {
            if (root.t < 0.5) {
                root.visible = false;
                if (PillState.owner === "applauncher")
                    PillState.owner = "";
            }
        }
    }

    Connections {
        target: AppLauncherState
        function onLauncherVisibleChanged() {
            if (AppLauncherState.launcherVisible)
                root.openLauncher();
            else
                root.close();
        }
    }

    // another panel took the pill, so this one gives way
    Connections {
        target: PillState
        function onOwnerChanged() {
            if (PillState.owner !== "applauncher" && root.visible)
                AppLauncherState.launcherVisible = false;
        }
    }

    onVisibleChanged: {
        if (visible)
            searchInput.forceActiveFocus();
    }

    // ── Activate ───────────────────────────────────────────────────────────
    function enterMode(name) {
        mode = name;
        searchInput.text = "";
    }

    function activate(r) {
        if (!r)
            return;
        if (r.kind === "app") {
            AppLauncherState.recordLaunch(r.entry.id);
            r.entry.execute();
            AppLauncherState.hide();
        } else if (r.kind === "mode") {
            enterMode(r.value);
        } else if (r.kind === "calc") {
            // "--" so a negative answer is not read as an option
            Quickshell.execDetached(["wl-copy", "--", r.value]);
            AppLauncherState.hide();
        }
    }

    // ── Navigation ─────────────────────────────────────────────────────────
    function navigate(delta) {
        if (results.length === 0)
            return;
        selectedIndex = (selectedIndex + delta + results.length) % results.length;
        listView.positionViewAtIndex(selectedIndex, ListView.Contain);
    }

    // ── Colours ────────────────────────────────────────────────────────────
    readonly property color accentFill: Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.18)

    // the calculator only evaluates while it is the open mode
    Binding {
        target: Calc
        property: "expression"
        value: root.mode === "calc" ? root.searchQuery.trim() : ""
    }

    // only the card takes clicks; everything around it passes through
    mask: Region { item: outline }

    // ── Card ───────────────────────────────────────────────────────────────
    // the outline is a notch, drawn behind the card and sized to it
    Notch {
        id: outline
        bodyWidth: card.width
        bodyHeight: card.height
        x: card.x - bodyX
        y: card.y
    }

    Rectangle {
        id: card

        readonly property real fromW: PillState.pillWidth
        readonly property real fromH: PillState.pillHeight

        width: fromW + (root.panelW - fromW) * root.t
        height: fromH + (root.panelH - fromH) * root.t
        x: (root.width - width) / 2
        y: PillState.pillTop
        color: "transparent"
        clip: true

        // content fades in during the second half of the morph
        Column {
            anchors {
                top: parent.top
                topMargin: 12
                left: parent.left
                leftMargin: 12
                right: parent.right
                rightMargin: 12
            }
            spacing: 8
            opacity: Math.max(0, (root.t - 0.5) * 2)

            // ── Search line, with the match count on the right ─────────────
            Item {
                width: parent.width
                height: 34

                Text {
                    id: searchGlyph
                    anchors.left: parent.left
                    anchors.leftMargin: 14
                    anchors.verticalCenter: parent.verticalCenter
                    text: root.modeInfo ? root.modeInfo.glyph : "󰍉"
                    color: root.modeInfo ? Theme.primary : Qt.alpha(Theme.fg, 0.45)
                    font.family: Theme.fontFamily
                    font.pixelSize: 15
                }

                Text {
                    anchors.left: searchGlyph.right
                    anchors.leftMargin: 10
                    anchors.right: countText.left
                    anchors.rightMargin: 10
                    anchors.verticalCenter: parent.verticalCenter
                    text: root.modeInfo ? root.modeInfo.placeholder : "Search apps"
                    color: Theme.fg
                    opacity: 0.28
                    font.family: Theme.fontFamily
                    font.pixelSize: 13
                    elide: Text.ElideRight
                    visible: searchInput.text === ""
                }

                TextInput {
                    id: searchInput
                    anchors.left: searchGlyph.right
                    anchors.leftMargin: 10
                    anchors.right: countText.left
                    anchors.rightMargin: 10
                    anchors.verticalCenter: parent.verticalCenter
                    color: Theme.fg
                    selectionColor: root.accentFill
                    font.family: Theme.fontFamily
                    font.pixelSize: 13
                    clip: true

                    onTextChanged: {
                        // a bang plus space moves into its mode, and the text
                        // carries on after it
                        if (root.mode === "") {
                            var p = Modes.parse(text);
                            if (p.mode !== "") {
                                root.mode = p.mode;
                                text = p.text;
                                return;
                            }
                        }
                        root.searchQuery = text;
                    }

                    Keys.onPressed: function (event) {
                        if (event.key === Qt.Key_Up) {
                            root.navigate(-1);
                            event.accepted = true;
                        } else if (event.key === Qt.Key_Down) {
                            root.navigate(1);
                            event.accepted = true;
                        } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                            root.activate(root.results[root.selectedIndex]);
                            event.accepted = true;
                        } else if (event.key === Qt.Key_Backspace && root.mode !== "" && text === "") {
                            // Backspace on an empty line leaves the mode
                            root.mode = "";
                            event.accepted = true;
                        } else if (event.key === Qt.Key_Escape) {
                            AppLauncherState.hide();
                            event.accepted = true;
                        }
                    }
                }

                Text {
                    id: countText
                    anchors.right: parent.right
                    anchors.rightMargin: 14
                    anchors.verticalCenter: parent.verticalCenter
                    text: root.mode !== "" ? "" : root.results.length + " / " + DesktopEntries.applications.values.length
                    color: Theme.fg
                    opacity: 0.35
                    font.family: Theme.fontFamilyAlt
                    font.pixelSize: 11
                }
            }

            // ── App list ───────────────────────────────────────────────────
            ListView {
                id: listView
                width: parent.width
                height: Math.max(1, Math.min(root.results.length, root.maxVisible)) * root.itemH
                model: root.results
                clip: true
                interactive: false

                // says why the list is empty
                Text {
                    anchors.centerIn: parent
                    visible: root.results.length === 0
                    text: root.emptyText
                    color: Theme.fg
                    opacity: 0.28
                    font.family: Theme.fontFamily
                    font.pixelSize: 13
                }

                // wheel scrolls the selection, as before
                MouseArea {
                    anchors.fill: parent
                    onWheel: function (wheel) {
                        if (wheel.angleDelta.y < 0)
                            root.navigate(1);
                        else
                            root.navigate(-1);
                    }
                }

                delegate: Rectangle {
                    id: appRow
                    required property var modelData
                    required property int index

                    width: listView.width
                    height: root.itemH
                    radius: 10
                    color: root.selectedIndex === index ? root.accentFill : "transparent"
                    Behavior on color { ColorAnimation { duration: 100 } }

                    readonly property bool sel: root.selectedIndex === index

                    // icon, name and category
                    Row {
                        anchors {
                            left: parent.left
                            right: returnHint.left
                            verticalCenter: parent.verticalCenter
                            leftMargin: 10
                            rightMargin: 8
                        }
                        spacing: 12

                        Item {
                            width: 26
                            height: 26
                            anchors.verticalCenter: parent.verticalCenter

                            Image {
                                id: appIcon
                                anchors.fill: parent
                                source: appRow.modelData.icon !== "" ? "image://icon/" + appRow.modelData.icon : ""
                                smooth: true
                                mipmap: true
                            }

                            // the row's glyph, else a letter while there is no icon
                            Text {
                                anchors.centerIn: parent
                                visible: appIcon.status !== Image.Ready
                                text: appRow.modelData.glyph !== "" ? appRow.modelData.glyph : appRow.modelData.title.charAt(0).toUpperCase()
                                font.family: Theme.fontFamily
                                font.pixelSize: appRow.modelData.glyph !== "" ? 17 : 14
                                font.weight: appRow.modelData.glyph !== "" ? Font.Normal : Font.Bold
                                color: appRow.sel ? Theme.primary : Theme.fg
                            }
                        }

                        Column {
                            anchors.verticalCenter: parent.verticalCenter
                            width: parent.width - 26 - parent.spacing
                            spacing: 2

                            Text {
                                width: parent.width
                                text: appRow.modelData.title
                                elide: Text.ElideRight
                                font.family: Theme.fontFamily
                                font.pixelSize: 13
                                font.weight: appRow.sel ? Font.Medium : Font.Normal
                                color: Theme.fg
                                opacity: appRow.sel ? 1 : 0.8
                            }

                            Text {
                                width: parent.width
                                visible: text !== ""
                                text: appRow.modelData.subtitle
                                elide: Text.ElideRight
                                font.family: Theme.fontFamily
                                font.pixelSize: 10
                                color: Theme.fg
                                opacity: 0.35
                            }
                        }
                    }

                    // return hint on the selected row
                    Text {
                        id: returnHint
                        anchors.right: parent.right
                        anchors.rightMargin: 12
                        anchors.verticalCenter: parent.verticalCenter
                        text: "↵"
                        visible: appRow.sel
                        color: Theme.fg
                        opacity: 0.5
                        font.family: Theme.fontFamilyAlt
                        font.pixelSize: 12
                    }

                    MouseArea {
                        anchors.fill: parent
                        hoverEnabled: true
                        onEntered: root.selectedIndex = appRow.index
                        onClicked: root.activate(appRow.modelData)
                    }
                }
            }

            // ── Keybind footer ─────────────────────────────────────────────
            Text {
                width: parent.width
                horizontalAlignment: Text.AlignHCenter
                text: root.mode === "calc" ? "↵ copy   ⌫ back   esc close" : "↑↓ move   ↵ launch   esc close"
                color: Theme.fg
                opacity: 0.25
                font.family: Theme.fontFamilyAlt
                font.pixelSize: 10
            }
        }
    }
}
