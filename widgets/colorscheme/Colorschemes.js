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
    },
    {
        id: "catppuccin-mocha", name: "Catppuccin Mocha",
        palette: ["#1e1e2e", "#181825", "#cdd6f4", "#313244", "#89b4fa", "#fab387", "#f38ba8", "#6c7086"],
        ansi: ["#45475a", "#f38ba8", "#a6e3a1", "#f9e2af", "#89b4fa", "#f5c2e7", "#94e2d5", "#bac2de",
               "#585b70", "#f38ba8", "#a6e3a1", "#f9e2af", "#89b4fa", "#f5c2e7", "#94e2d5", "#a6adc8"]
    },
    {
        id: "catppuccin-macchiato", name: "Catppuccin Macchiato",
        palette: ["#24273a", "#1e2030", "#cad3f5", "#363a4f", "#8aadf4", "#f5a97f", "#ed8796", "#6e738d"],
        ansi: ["#494d64", "#ed8796", "#a6da95", "#eed49f", "#8aadf4", "#f5bde6", "#8bd5ca", "#b8c0e0",
               "#5b6078", "#ed8796", "#a6da95", "#eed49f", "#8aadf4", "#f5bde6", "#8bd5ca", "#a5adcb"]
    },
    {
        id: "catppuccin-frappe", name: "Catppuccin Frappé",
        palette: ["#303446", "#292c3c", "#c6d0f5", "#414559", "#8caaee", "#ef9f76", "#e78284", "#737994"],
        ansi: ["#51576d", "#e78284", "#a6d189", "#e5c890", "#8caaee", "#f4b8e4", "#81c8be", "#b5bfe2",
               "#626880", "#e78284", "#a6d189", "#e5c890", "#8caaee", "#f4b8e4", "#81c8be", "#a5adce"]
    },
    {
        id: "catppuccin-latte", name: "Catppuccin Latte",
        palette: ["#eff1f5", "#e6e9ef", "#4c4f69", "#ccd0da", "#1e66f5", "#fe640b", "#d20f39", "#9ca0b0"],
        ansi: ["#ccd0da", "#d20f39", "#40a02b", "#df8e1d", "#1e66f5", "#ea76cb", "#179299", "#6c6f85",
               "#bcc0cc", "#d20f39", "#40a02b", "#df8e1d", "#1e66f5", "#ea76cb", "#179299", "#5c5f77"]
    },
    {
        id: "dracula", name: "Dracula",
        palette: ["#282a36", "#21222c", "#f8f8f2", "#44475a", "#8be9fd", "#ffb86c", "#ff5555", "#6272a4"],
        ansi: ["#21222c", "#ff5555", "#50fa7b", "#f1fa8c", "#8be9fd", "#ff79c6", "#8be9fd", "#f8f8f2",
               "#6272a4", "#ff5555", "#50fa7b", "#f1fa8c", "#8be9fd", "#ff79c6", "#8be9fd", "#ffffff"]
    },
    {
        id: "solarized-dark", name: "Solarized Dark",
        palette: ["#002b36", "#073642", "#839496", "#586e75", "#268bd2", "#cb4b16", "#dc322f", "#657b83"],
        ansi: ["#073642", "#dc322f", "#859900", "#b58900", "#268bd2", "#d33682", "#2aa198", "#eee8d5",
               "#002b36", "#cb4b16", "#586e75", "#657b83", "#839496", "#6c71c4", "#93a1a1", "#fdf6e3"]
    },
    {
        id: "rose-pine", name: "Rosé Pine",
        palette: ["#191724", "#1f1d2e", "#e0def4", "#26233a", "#9ccfd8", "#f6c177", "#eb6f92", "#6e6a86"],
        ansi: ["#26233a", "#eb6f92", "#31748f", "#f6c177", "#9ccfd8", "#c4a7e7", "#ebbcba", "#e0def4",
               "#6e6a86", "#eb6f92", "#31748f", "#f6c177", "#9ccfd8", "#c4a7e7", "#ebbcba", "#908caa"]
    },
    {
        id: "monochrome", name: "Monochrome",
        palette: ["#121212", "#1c1c1c", "#e0e0e0", "#333333", "#ffffff", "#b0b0b0", "#777777", "#555555"],
        ansi: ["#121212", "#333333", "#555555", "#777777", "#999999", "#bbbbbb", "#dddddd", "#ffffff",
               "#262626", "#444444", "#666666", "#888888", "#aaaaaa", "#cccccc", "#eeeeee", "#ffffff"]
    },
    {
        id: "ayu", name: "Ayu",
        palette: ["#0b0e14", "#131721", "#bfbdb6", "#272d38", "#e6b450", "#73b8ff", "#f07171", "#575f66"],
        ansi: ["#0b0e14", "#f07171", "#73d066", "#fff352", "#73b8ff", "#dfbfff", "#95e6cb", "#bfbdb6",
               "#575f66", "#f07171", "#73d066", "#fff352", "#73b8ff", "#dfbfff", "#95e6cb", "#ffffff"]
    },
    {
        id: "moonfly", name: "Moonfly",
        palette: ["#080808", "#1c1c1c", "#bdbdbd", "#323437", "#80a0ff", "#e3c78a", "#ff5d5d", "#949494"],
        ansi: ["#323437", "#ff5d5d", "#8cc85f", "#e3c78a", "#80a0ff", "#cf87e8", "#79dac8", "#c6c6c6",
               "#949494", "#ff5189", "#36c692", "#c6c684", "#74b2ff", "#ae81ff", "#85dc85", "#e4e4e4"]
    }
]

function indexOfId(id) {
    for (let i = 0; i < SCHEMES.length; i++)
        if (SCHEMES[i].id === id)
            return i
    return -1
}
