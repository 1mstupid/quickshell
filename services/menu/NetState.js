.pragma library

// Reads the output of the state script in Net.qml: one tagged line each for the
// Wi-Fi radio and the Bluetooth adapter, then one per network device and per
// saved connection.
//   wifi:enabled
//   bt:on | bt:off | bt:absent
//   dev:DEVICE:TYPE:STATE:CONNECTION
//   con:NAME:TYPE:ACTIVE
// A missing line, or a tool that is not installed, leaves its fields off. No
// QML types, so it can be tested with plain node.

// nmcli escapes a colon inside a name as "\:"
function unescape(s) {
    return s.replace(/\\:/g, ":")
}

function parse(lines) {
    const out = {
        hasWifi: false,
        wifiOn: false,
        wifiConn: "",
        wiredUp: false,
        btPresent: false,
        btOn: false,
        vpnCount: 0,
        vpnActive: []
    }

    for (const line of lines) {
        const i = line.indexOf(":")
        if (i < 0)
            continue
        const tag = line.slice(0, i)
        const rest = line.slice(i + 1)

        if (tag === "wifi") {
            out.wifiOn = rest.trim() === "enabled"
        } else if (tag === "bt") {
            const v = rest.trim()
            out.btPresent = v === "on" || v === "off"
            out.btOn = v === "on"
        } else if (tag === "dev") {
            const p = rest.split(":")
            if (p.length < 3)
                continue
            // "connected" and "connected (externally)", but not "disconnected"
            const up = p[2].indexOf("connected") === 0
            if (p[1] === "wifi") {
                out.hasWifi = true
                if (up)
                    out.wifiConn = unescape(p.slice(3).join(":"))
            } else if (p[1] === "ethernet" && up) {
                out.wiredUp = true
            }
        } else if (tag === "con") {
            const p = rest.split(":")
            if (p.length < 3)
                continue
            const type = p[p.length - 2]
            // the profiles the VPN list shows: VPN and WireGuard, and external tunnels
            if (type !== "vpn" && type !== "wireguard" && type !== "tun")
                continue
            out.vpnCount++
            if (p[p.length - 1] === "yes")
                out.vpnActive.push(unescape(p.slice(0, p.length - 2).join(":")))
        }
    }
    return out
}
