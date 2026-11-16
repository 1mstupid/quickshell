.pragma library

// Every setting in settings.json: its key, type and default, for a number its range, and a
// label and group for the settings panel. UserSettings reads, checks and writes the file
// through this list, so a new setting is one entry here and one property there.
// A setting is a "bool", a "number" or a "text" (a non-empty string).
// For the panel a number also has a `step` and a `unit`, and a widget a `layout` id: its
// visibility is kept in layout.json once that has one (see WidgetLayout), so the panel
// goes through that. No QML types, so the list can be checked with plain node.

// the pages of the panel, in order; a group with no setting has no page
const GROUPS = [
    { id: "bar", title: "Bar & Island", glyph: "󰍜" },
    { id: "appearance", title: "Appearance", glyph: "󰏘" },
    { id: "clock", title: "Clock", glyph: "󰅐" },
    { id: "widgets", title: "Widgets", glyph: "󰕮" },
    { id: "controlCenter", title: "Control Center", glyph: "󰘮" }
]

const SETTINGS = [
    // the bar and its panels
    { key: "pill", type: "bool", def: false, group: "bar", label: "Floating pill" },
    { key: "wave", type: "bool", def: false, group: "bar", label: "Media Module" },
    { key: "workspaces", type: "bool", def: false, group: "bar", label: "Workspaces Module" },
    { key: "recording", type: "bool", def: false, group: "bar", label: "Recording Module" },
    { key: "pomo", type: "bool", def: false, group: "bar", label: "Pomodoro Module" },


    { key: "cornerRadius", type: "number", def: 26, min: 0, max: 40, step: 1, unit: "px", group: "bar", label: "Corner radius" },

    // fonts: the body font is all the text and the icons, so it should be a Nerd Font; the display
    // font is the big figures
    { key: "bodyFont", type: "text", def: "SFProText Nerd Font", group: "appearance", label: "Body font" },
    { key: "displayFont", type: "text", def: "SFProDisplay Nerd Font", group: "appearance", label: "Display font" },

    // 12 or 24 hours on the clocks (the bar and the lock screen)
    { key: "clock24", type: "bool", def: false, group: "clock", label: "24-hour clock" },

    // the corner widgets and the media player
    { key: "usageRing", type: "bool", def: true, layout: "usage", group: "widgets", label: "Usage ring" },
    { key: "focusWidget", type: "bool", def: true, layout: "focus", group: "widgets", label: "Focus" },
    { key: "todoWidget", type: "bool", def: true, layout: "todo", group: "widgets", label: "Todo" },
    { key: "habitsWidget", type: "bool", def: true, layout: "habits", group: "widgets", label: "Habits" },
    { key: "mediaWidget", type: "bool", def: true, layout: "media", group: "widgets", label: "Media player" },

    // what the control panel offers
    { key: "wifi", type: "bool", def: true, group: "controlCenter", label: "Wi-Fi" },
    { key: "bluetooth", type: "bool", def: true, group: "controlCenter", label: "Bluetooth" },
    { key: "vpn", type: "bool", def: true, group: "controlCenter", label: "VPN" },
    { key: "brightness", type: "bool", def: true, group: "controlCenter", label: "Display" },
    { key: "powerProfile", type: "bool", def: true, group: "controlCenter", label: "Power profile" },
    { key: "nightLight", type: "bool", def: true, group: "controlCenter", label: "Night light" },
    { key: "keepAwake", type: "bool", def: true, group: "controlCenter", label: "Keep awake" },
    { key: "screenshot", type: "bool", def: true, group: "controlCenter", label: "Screenshot" }
]

function find(key) {
    return SETTINGS.find(s => s.key === key)
}

function defaultOf(key) {
    const s = find(key)
    return s ? s.def : undefined
}

// `v` as the setting takes it, or undefined for the wrong type. A number is held to its range.
function normalize(s, v) {
    if (s.type === "bool")
        return typeof v === "boolean" ? v : undefined
    if (s.type === "number") {
        if (typeof v !== "number" || !isFinite(v))
            return undefined
        return Math.min(s.max, Math.max(s.min, v))
    }
    if (s.type === "text") {
        if (typeof v !== "string")
            return undefined
        const t = v.trim()
        return t !== "" && t.length <= 100 ? t : undefined
    }
    return undefined
}

// The file's text as { values, extra }: a value for every setting (the default for one that is
// missing or of the wrong type, and for a bad file), and the keys of the file that are not
// settings, so that writing the file back does not lose them.
function parse(text) {
    let d = null
    try {
        d = JSON.parse(text)
    } catch (e) {
        d = null
    }
    if (typeof d !== "object" || d === null || Array.isArray(d))
        d = {}

    const values = {}
    for (const s of SETTINGS) {
        const v = normalize(s, d[s.key])
        values[s.key] = v === undefined ? s.def : v
    }
    const extra = {}
    for (const k of Object.keys(d))
        if (!find(k))
            extra[k] = d[k]
    return { values: values, extra: extra }
}

// the text of the file: every setting, in the order of the list, then the extra keys
function serialize(values, extra) {
    return JSON.stringify(Object.assign({}, values, extra), null, 2) + "\n"
}
