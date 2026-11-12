.pragma library

// Reads what `ss` says is listening and which of it other machines can reach.
// The input is two commands joined by a marker line (see Ports.qml):
//   ss -tulpnH
//   ===CONNECTIONS===
//   ss -tnH state established
// Lines, as ss prints them:
//   tcp LISTEN 0 511 127.0.0.1:5173 0.0.0.0:* users:(("node",pid=1781,fd=22))
//   udp UNCONN 0 0   0.0.0.0:5353   0.0.0.0:*
//   0 0 192.168.1.5:22 192.168.1.9:51234              (an established connection)
// Without root ss only names the user's own processes, so a row can have no owner.
// No QML types, so it can be tested with plain node. The idea of leading with
// "open to the network" comes from k4-puertos (MIT), https://github.com/k4ditano/k4-puertos

var MARK = "===CONNECTIONS==="

// the address is host:port, and the host can hold colons ([::1]:80), so cut at the last one
function portOf(addr) {
    const i = String(addr).lastIndexOf(":")
    return i < 0 ? 0 : parseInt(String(addr).substring(i + 1), 10) || 0
}

function hostOf(addr) {
    const i = String(addr).lastIndexOf(":")
    return i < 0 ? "" : String(addr).substring(0, i)
}

// 127.x and ::1 are this machine only; 0.0.0.0, [::], * and a real interface address
// can all be reached from the network. A zone suffix (127.0.0.53%lo) is not part of it.
function isExposed(host) {
    const h = String(host).replace(/%.*$/, "")
    return !(h === "::1" || h === "[::1]" || h.indexOf("127.") === 0)
}

// Where to point a client: a wildcard bind is reached by localhost, and only a
// process bound to one real address is reached by that address.
function addressOf(row) {
    const wild = row.host === "" || row.host === "0.0.0.0" || row.host === "*"
        || row.host.indexOf("[::]") === 0
    const host = row.exposed && !wild ? row.host : "localhost"
    return host + ":" + row.port
}

// only tcp can be opened in a browser; a udp port in one is nothing
function isWeb(row) {
    return String(row.proto).indexOf("tcp") === 0
}

// Rows, exposed ones first and then by port. The same service listening on IPv4 and
// IPv6 is one row, exposed if either side is; `conns` counts the live tcp connections
// to its port.
function parse(text) {
    const parts = String(text).split(MARK)
    const listening = (parts[0] || "").split("\n")
    const connected = (parts[1] || "").split("\n")

    const conns = {}
    for (const line of connected) {
        const c = line.trim().split(/\s+/)
        if (c.length < 4)
            continue
        const port = portOf(c[2])
        if (port > 0)
            conns[port] = (conns[port] || 0) + 1
    }

    const byKey = {}
    const rows = []
    for (const line of listening) {
        const l = line.trim()
        const c = l.split(/\s+/)
        if (c.length < 5)
            continue
        const port = portOf(c[4])
        if (port <= 0)
            continue

        let process = ""
        let pid = 0
        const m = l.match(/users:\(\("([^"]+)",pid=(\d+)/)
        if (m) {
            process = m[1]
            pid = parseInt(m[2], 10) || 0
        }

        const host = hostOf(c[4])
        const exposed = isExposed(host)
        const key = c[0] + "/" + port + "/" + process
        if (byKey[key]) {
            byKey[key].exposed = byKey[key].exposed || exposed
            continue
        }
        const row = { key: key, proto: c[0], port: port, host: host, process: process, pid: pid,
                      exposed: exposed, conns: c[0].indexOf("tcp") === 0 ? (conns[port] || 0) : 0 }
        byKey[key] = row
        rows.push(row)
    }

    rows.sort((a, b) => a.exposed !== b.exposed ? (a.exposed ? -1 : 1) : a.port - b.port)
    return rows
}
