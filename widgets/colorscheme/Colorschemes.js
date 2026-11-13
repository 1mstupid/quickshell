.pragma library

// The colour schemes the picker offers. `palette` and `ansi` are in the order the
// wallpaper-theme script takes them (the same as WallpaperPalette.derive):
//   palette: background, background-alt, foreground, border, primary, secondary, alert, disabled
//   ansi:    the 16 terminal colours, black to bright white
// The "wallpaper" entry has none: its colours are derived from the wallpaper in use.
// No QML types, so the list can be checked with plain node.
const SCHEMES = [
    {
        id: "gruvbox", name: "Gruvbox",
        palette: ["#282828", "#3c3836", "#ebdbb2", "#504945", "#fabd2f", "#8ec07c", "#fb4934", "#928374"],
        ansi: ["#282828", "#cc241d", "#98971a", "#d79921", "#458588", "#b16286", "#689d6a", "#a89984",
               "#928374", "#fb4934", "#b8bb26", "#fabd2f", "#83a598", "#d3869b", "#8ec07c", "#ebdbb2"]
    },
    { id: "wallpaper", name: "Wallpaper" },
    {
        id: "nord", name: "Nord",
        palette: ["#2e3440", "#3b4252", "#d8dee9", "#434c5e", "#88c0d0", "#81a1c1", "#bf616a", "#4c566a"],
        ansi: ["#3b4252", "#bf616a", "#a3be8c", "#ebcb8b", "#81a1c1", "#b48ead", "#88c0d0", "#e5e9f0",
               "#4c566a", "#bf616a", "#a3be8c", "#ebcb8b", "#81a1c1", "#b48ead", "#8fbcbb", "#eceff4"]
    },
    {
        id: "tokyonight", name: "Tokyo Night",
        palette: ["#1a1b26", "#24283b", "#c0caf5", "#3b4261", "#7aa2f7", "#7dcfff", "#f7768e", "#565f89"],
        ansi: ["#15161e", "#f7768e", "#9ece6a", "#e0af68", "#7aa2f7", "#bb9af7", "#7dcfff", "#a9b1d6",
               "#414868", "#f7768e", "#9ece6a", "#e0af68", "#7aa2f7", "#bb9af7", "#7dcfff", "#c0caf5"]
    },
    {
        id: "everforest", name: "Everforest",
        palette: ["#2d353b", "#343f44", "#d3c6aa", "#475258", "#a7c080", "#83c092", "#e67e80", "#859289"],
        ansi: ["#475258", "#e67e80", "#a7c080", "#dbbc7f", "#7fbbb3", "#d699b6", "#83c092", "#d3c6aa",
               "#859289", "#e67e80", "#a7c080", "#dbbc7f", "#7fbbb3", "#d699b6", "#83c092", "#d3c6aa"]
    }
]

function indexOfId(id) {
    for (let i = 0; i < SCHEMES.length; i++)
        if (SCHEMES[i].id === id)
            return i
    return -1
}
