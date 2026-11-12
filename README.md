# Quickshell desktop shell

A Quickshell desktop shell in QML, for NixOS.

## Credits

- **Ports page** (the focus notch's third page, `services/Ports.qml` and `services/PortsParse.js`):
  the idea of leading with what the network can reach, merging IPv4 and IPv6 listeners, polling
  `ss` only while the page is open, and closing a process with a two-tap confirmation follows
  [k4-puertos](https://github.com/k4ditano/k4-puertos) (MIT). The code is written for this shell.
