# Quickshell desktop shell

A Quickshell desktop shell in QML, for NixOS.

## Credits

- **Lyrics widget** (`widgets/lyrics/`, `widgets/bar/media/LyricsMath.js`): adapted from
  [sekaipop](https://github.com/blapples/sekaipop) by blapples, GPL-3.0. `LyricsMath.js` is its
  lyric timing maths, and `LyricsLine.qml` and `LyricsWidget.qml` follow its stack, sung-colour
  and marker design. The word stickers, diamonds and bursts (`LyricsWord.qml`, `DiamondDot.qml`,
  `Burst.qml`), the lrclib fetch and the wiring to this shell are written for this repository.
  Because this code is GPL-3.0, the repository is licensed under GPL-3.0 as well (see `LICENSE`).
- **Ports page** (the focus notch's third page, `services/Ports.qml` and `services/PortsParse.js`):
  the idea of leading with what the network can reach, merging IPv4 and IPv6 listeners, polling
  `ss` only while the page is open, and closing a process with a two-tap confirmation follows
  [k4-puertos](https://github.com/k4ditano/k4-puertos) (MIT). The code is written for this shell.

## Licence

This repository is licensed under the GNU General Public License v3.0 (see `LICENSE`).
