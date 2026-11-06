// Run: node test_net_state.js
// Loads NetState.js (stripping the QML-only .pragma line) and checks it on
// sample output of the state script in Net.qml.
const fs = require("fs")
const path = require("path")
const assert = require("assert")

const src = fs.readFileSync(path.join(__dirname, "NetState.js"), "utf8")
    .replace(/^\.pragma library\s*$/m, "")
const { parse } = new Function(src + "\nreturn { parse };")()

let failures = 0
function test(name, fn) {
    try {
        fn()
        console.log("ok   ", name)
    } catch (e) {
        failures++
        console.log("FAIL ", name, "\n     ", e.message)
    }
}

test("a desktop on ethernet: no wifi device, wired up", () => {
    const s = parse(["wifi:enabled", "dev:enp5s0:ethernet:connected:Wired connection 1",
        "dev:lo:loopback:connected (externally):lo", "bt:absent"])
    assert.strictEqual(s.hasWifi, false)
    assert.strictEqual(s.wiredUp, true)
    assert.strictEqual(s.btPresent, false)
    assert.strictEqual(s.vpnCount, 0)
})

test("a laptop on wifi with bluetooth on", () => {
    const s = parse(["wifi:enabled", "dev:wlp2s0:wifi:connected:Home 5G",
        "dev:enp3s0:ethernet:unavailable:", "bt:on"])
    assert.strictEqual(s.hasWifi, true)
    assert.strictEqual(s.wifiOn, true)
    assert.strictEqual(s.wifiConn, "Home 5G")
    assert.strictEqual(s.wiredUp, false)
    assert.strictEqual(s.btPresent, true)
    assert.strictEqual(s.btOn, true)
})

test("wifi radio off: the device is there, not connected, no name", () => {
    const s = parse(["wifi:disabled", "dev:wlp2s0:wifi:unavailable:", "bt:off"])
    assert.strictEqual(s.hasWifi, true)
    assert.strictEqual(s.wifiOn, false)
    assert.strictEqual(s.wifiConn, "")
    assert.strictEqual(s.btPresent, true)
    assert.strictEqual(s.btOn, false)
})

test("a disconnected device is not connected", () => {
    const s = parse(["dev:wlp2s0:wifi:disconnected:", "dev:enp3s0:ethernet:disconnected:"])
    assert.strictEqual(s.wifiConn, "")
    assert.strictEqual(s.wiredUp, false)
})

test("a network name with a colon is unescaped", () => {
    const s = parse(["dev:wlp2s0:wifi:connected:Cafe\\: Guest"])
    assert.strictEqual(s.wifiConn, "Cafe: Guest")
})

test("vpn profiles are counted, the active ones named", () => {
    const s = parse(["con:Home 5G:802-11-wireless:yes", "con:Work VPN:vpn:no",
        "con:wg0:wireguard:yes", "con:corp:tun:no", "con:Wired connection 1:802-3-ethernet:yes"])
    assert.strictEqual(s.vpnCount, 3)
    assert.deepStrictEqual(s.vpnActive, ["wg0"])
})

test("a vpn name with a colon keeps it", () => {
    const s = parse(["con:Work\\: EU:vpn:yes"])
    assert.deepStrictEqual(s.vpnActive, ["Work: EU"])
})

test("no output, or junk lines, leave everything off", () => {
    for (const lines of [[], ["", "nonsense", "dev:", "con:x"]]) {
        const s = parse(lines)
        assert.strictEqual(s.hasWifi, false)
        assert.strictEqual(s.wifiOn, false)
        assert.strictEqual(s.btPresent, false)
        assert.strictEqual(s.vpnCount, 0)
        assert.deepStrictEqual(s.vpnActive, [])
    }
})

process.exitCode = failures ? 1 : 0
