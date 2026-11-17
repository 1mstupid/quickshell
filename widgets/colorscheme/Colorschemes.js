.pragma library

// The colour schemes the picker offers. `palette` and `ansi` are in the order the
// wallpaper-theme script takes them (the same as WallpaperPalette.derive):
//   palette: background, background-alt, foreground, border, primary, secondary, alert, disabled
//   ansi:    the 16 terminal colours, black to bright white
//   light:   true for a light scheme; the script then gets --light and picks its light background
// The "wallpaper" entry has none: its colours are derived from the wallpaper in use, and
// those are always a dark scheme.
// No QML types, so the list can be checked with plain node.
const SCHEMES = [
    {
        id: "gruvbox", name: "Gruvbox",
        dark: {
            palette: ["#282828", "#3c3836", "#ebdbb2", "#504945", "#fabd2f", "#8ec07c", "#fb4934", "#928374"],
            ansi: ["#282828", "#cc241d", "#98971a", "#d79921", "#458588", "#b16286", "#689d6a", "#a89984",
                   "#928374", "#fb4934", "#b8bb26", "#fabd2f", "#83a598", "#d3869b", "#8ec07c", "#ebdbb2"]
        },
        light: {
            palette: ["#fbf1c7", "#ebdbb2", "#3c3836", "#d5c4a1", "#b57614", "#427b58", "#9d0006", "#928374"],
            ansi: ["#fbf1c7", "#cc241d", "#98971a", "#d79921", "#458588", "#b16286", "#689d6a", "#7c6f64",
                   "#928374", "#9d0006", "#79740e", "#b57614", "#076678", "#8f3f71", "#427b58", "#3c3836"]
        }
    },
    { id: "wallpaper", name: "Wallpaper" },
    {
        id: "nord", name: "Nord",
        dark: {
            palette: ["#2e3440", "#3b4252", "#d8dee9", "#434c5e", "#88c0d0", "#81a1c1", "#bf616a", "#4c566a"],
            ansi: ["#3b4252", "#bf616a", "#a3be8c", "#ebcb8b", "#81a1c1", "#b48ead", "#88c0d0", "#e5e9f0",
                   "#4c566a", "#bf616a", "#a3be8c", "#ebcb8b", "#81a1c1", "#b48ead", "#8fbcbb", "#eceff4"]
        },
        light: {
            palette: ["#eceff4", "#e5e9f0", "#2e3440", "#d8dee9", "#5e81ac", "#81a1c1", "#bf616a", "#4c566a"],
            ansi: ["#eceff4", "#bf616a", "#719358", "#b58932", "#5e81ac", "#9a6c92", "#4c8e9e", "#4c566a",
                   "#d8dee9", "#bf616a", "#719358", "#b58932", "#5e81ac", "#9a6c92", "#4c8e9e", "#2e3440"]
        }
    },
    {
        id: "tokyonight", name: "Tokyo Night",
        dark: {
            palette: ["#1a1b26", "#24283b", "#c0caf5", "#3b4261", "#7aa2f7", "#7dcfff", "#f7768e", "#565f89"],
            ansi: ["#15161e", "#f7768e", "#9ece6a", "#e0af68", "#7aa2f7", "#bb9af7", "#7dcfff", "#a9b1d6",
                   "#414868", "#f7768e", "#9ece6a", "#e0af68", "#7aa2f7", "#bb9af7", "#7dcfff", "#c0caf5"]
        },
        light: {
            palette: ["#e1e2e7", "#d5d6db", "#3760bf", "#c4c8da", "#2e7de9", "#007197", "#f52a65", "#848cb5"],
            ansi: ["#e9e9ed", "#f52a65", "#587539", "#8c6c3e", "#2e7de9", "#9854f1", "#007197", "#6172b0",
                   "#a1a6c5", "#f52a65", "#587539", "#8c6c3e", "#2e7de9", "#9854f1", "#007197", "#3760bf"]
        }
    },
    {
        id: "everforest", name: "Everforest",
        dark: {
            palette: ["#2d353b", "#343f44", "#d3c6aa", "#475258", "#a7c080", "#83c092", "#e67e80", "#859289"],
            ansi: ["#475258", "#e67e80", "#a7c080", "#dbbc7f", "#7fbbb3", "#d699b6", "#83c092", "#d3c6aa",
                   "#859289", "#e67e80", "#a7c080", "#dbbc7f", "#7fbbb3", "#d699b6", "#83c092", "#d3c6aa"]
        },
        light: {
            palette: ["#fdf6e3", "#f4f0d9", "#5c6a72", "#e6e2cc", "#8da101", "#35a77c", "#f85552", "#939f91"],
            ansi: ["#5c6a72", "#f85552", "#8da101", "#dfa000", "#3a94c5", "#df69ba", "#35a77c", "#e0dcc7",
                   "#939f91", "#f85552", "#8da101", "#dfa000", "#3a94c5", "#df69ba", "#35a77c", "#4b565c"]
        }
    },
    {
        id: "catppuccin", name: "Catppuccin",
        dark: {
            palette: ["#1e1e2e", "#181825", "#cdd6f4", "#313244", "#89b4fa", "#fab387", "#f38ba8", "#6c7086"],
            ansi: ["#45475a", "#f38ba8", "#a6e3a1", "#f9e2af", "#89b4fa", "#f5c2e7", "#94e2d5", "#bac2de",
                   "#585b70", "#f38ba8", "#a6e3a1", "#f9e2af", "#89b4fa", "#f5c2e7", "#94e2d5", "#a6adc8"]
        },
        light: {
            palette: ["#eff1f5", "#e6e9ef", "#4c4f69", "#ccd0da", "#1e66f5", "#fe640b", "#d20f39", "#9ca0b0"],
            ansi: ["#ccd0da", "#d20f39", "#40a02b", "#df8e1d", "#1e66f5", "#ea76cb", "#179299", "#6c6f85",
                   "#bcc0cc", "#d20f39", "#40a02b", "#df8e1d", "#1e66f5", "#ea76cb", "#179299", "#5c5f77"]
        }
    },
    {
        id: "solarized", name: "Solarized",
        dark: {
            palette: ["#002b36", "#073642", "#839496", "#586e75", "#268bd2", "#cb4b16", "#dc322f", "#657b83"],
            ansi: ["#073642", "#dc322f", "#859900", "#b58900", "#268bd2", "#d33682", "#2aa198", "#eee8d5",
                   "#002b36", "#cb4b16", "#586e75", "#657b83", "#839496", "#6c71c4", "#93a1a1", "#fdf6e3"]
        },
        light: {
            palette: ["#fdf6e3", "#eee8d5", "#657b83", "#93a1a1", "#268bd2", "#cb4b16", "#dc322f", "#839496"],
            ansi: ["#073642", "#dc322f", "#859900", "#b58900", "#268bd2", "#d33682", "#2aa198", "#eee8d5",
                   "#002b36", "#cb4b16", "#586e75", "#657b83", "#839496", "#6c71c4", "#93a1a1", "#fdf6e3"]
        }
    },
    {
        id: "rose-pine", name: "Rosé Pine",
        dark: {
            palette: ["#191724", "#1f1d2e", "#e0def4", "#26233a", "#9ccfd8", "#f6c177", "#eb6f92", "#6e6a86"],
            ansi: ["#26233a", "#eb6f92", "#31748f", "#f6c177", "#9ccfd8", "#c4a7e7", "#ebbcba", "#e0def4",
                   "#6e6a86", "#eb6f92", "#31748f", "#f6c177", "#9ccfd8", "#c4a7e7", "#ebbcba", "#908caa"]
        },
        light: {
            palette: ["#faf4ed", "#fffaf3", "#575279", "#f2e9e1", "#56949f", "#ea9d34", "#b4637a", "#9893a5"],
            ansi: ["#f2e9e1", "#b4637a", "#286983", "#ea9d34", "#56949f", "#907aa9", "#d7827e", "#575279",
                   "#9893a5", "#b4637a", "#286983", "#ea9d34", "#56949f", "#907aa9", "#d7827e", "#797593"]
        }
    },
    {
        id: "monochrome", name: "Monochrome",
        dark: {
            palette: ["#121212", "#1c1c1c", "#e0e0e0", "#333333", "#ffffff", "#b0b0b0", "#777777", "#555555"],
            ansi: ["#121212", "#333333", "#555555", "#777777", "#999999", "#bbbbbb", "#dddddd", "#ffffff",
                   "#262626", "#444444", "#666666", "#888888", "#aaaaaa", "#cccccc", "#eeeeee", "#ffffff"]
        },
        light: {
            palette: ["#f5f5f5", "#eaeaea", "#1a1a1a", "#d4d4d4", "#000000", "#555555", "#777777", "#888888"],
            ansi: ["#1a1a1a", "#333333", "#4d4d4d", "#666666", "#808080", "#999999", "#b3b3b3", "#cccccc",
                   "#000000", "#262626", "#404040", "#595959", "#737373", "#8c8c8c", "#a6a6a6", "#f5f5f5"]
        }
    },
    {
        id: "ayu", name: "Ayu",
        dark: {
            palette: ["#0b0e14", "#131721", "#bfbdb6", "#272d38", "#e6b450", "#73b8ff", "#f07171", "#575f66"],
            ansi: ["#0b0e14", "#f07171", "#73d066", "#fff352", "#73b8ff", "#dfbfff", "#95e6cb", "#bfbdb6",
                   "#575f66", "#f07171", "#73d066", "#fff352", "#73b8ff", "#dfbfff", "#95e6cb", "#ffffff"]
        },
        light: {
            palette: ["#f8f9fa", "#f3f4f5", "#5c6166", "#e7eaed", "#ffaa33", "#399ee6", "#f07171", "#8a9199"],
            ansi: ["#1a1f29", "#f07171", "#86b300", "#f2ae49", "#399ee6", "#a37acc", "#4cbf99", "#f3f4f5",
                   "#8a9199", "#f07171", "#86b300", "#f2ae49", "#399ee6", "#a37acc", "#4cbf99", "#5c6166"]
        }
    },
    {
        id: "moonfly", name: "Moonfly",
        dark: {
            palette: ["#080808", "#1c1c1c", "#bdbdbd", "#323437", "#80a0ff", "#e3c78a", "#ff5d5d", "#949494"],
            ansi: ["#323437", "#ff5d5d", "#8cc85f", "#e3c78a", "#80a0ff", "#cf87e8", "#79dac8", "#c6c6c6",
                   "#949494", "#ff5189", "#36c692", "#c6c684", "#74b2ff", "#ae81ff", "#85dc85", "#e4e4e4"]
        }
    }
];

function indexOfId(id) {
    for (let i = 0; i < SCHEMES.length; i++)
        if (SCHEMES[i].id === id)
            return i
    return -1
}

function variantFor(scheme, isLight) {
    if (!scheme || scheme.id === "wallpaper") return null;
    return (isLight && scheme.light) ? scheme.light : (scheme.dark || scheme.light);
}

function isLightVariant(scheme, isLight) {
    return !!(scheme && scheme.id !== "wallpaper"
              && isLight && scheme.light);
}
