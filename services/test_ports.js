// Run: node test_ports.js
// Loads PortsParse.js (stripping the QML-only .pragma line) and checks it on
// sample output of ss, in the formats ss prints.
const fs = require("fs")
const path = require("path")
const assert = require("assert")

const src = fs.readFileSync(path.join(__dirname, "PortsParse.js"), "utf8")
    .replace(/^\.pragma library\s*$/m, "")
const { parse, portOf, hostOf, isExposed, addressOf, isWeb } = new Function(src + "\nreturn { parse, portOf, hostOf, isExposed, addressOf, isWeb };")()

let failures = 0
function test(name, fn) {
    try {
        fn()
        console.log("ok   ", name)
    } catch (e) {
        failures++
        console.log("FAIL ", name, "-", e.message)
    }
}

const sample = [
    'tcp   LISTEN 0 511  127.0.0.1:5173   0.0.0.0:*  users:(("node",pid=1781,fd=22))',
    'tcp   LISTEN 0 128  0.0.0.0:22       0.0.0.0:*',
    'tcp   LISTEN 0 128  [::]:22          [::]:*',
    'tcp   LISTEN 0 4096 127.0.0.53%lo:53 0.0.0.0:*',
    'tcp   LISTEN 0 511  0.0.0.0:3000     0.0.0.0:*  users:(("next-server",pid=900,fd=19))',
    'tcp   LISTEN 0 511  [::]:3000        [::]:*     users:(("next-server",pid=900,fd=20))',
    'tcp   LISTEN 0 10   [::1]:631        [::]:*     users:(("cupsd",pid=640,fd=7))',
    'udp   UNCONN 0 0    0.0.0.0:5353     0.0.0.0:*  users:(("avahi-daemon",pid=700,fd=12))',
    'tcp   LISTEN 0 5    192.168.1.5:8080 0.0.0.0:*  users:(("python3",pid=1200,fd=3))',
].join("\n")
const conns = [
    "0 0 192.168.1.5:22 192.168.1.9:51234",
    "0 0 127.0.0.1:5173 127.0.0.1:40000",
    "0 0 127.0.0.1:5173 127.0.0.1:40002",
    "0 0 [::1]:3000 [::1]:41000",
    "0 0 [::ffff:192.168.1.5]:3000 [::ffff:192.168.1.9]:5000",
].join("\n")
const text = sample + "\n===CONNECTIONS===\n" + conns + "\n"

test("ports and hosts are cut at the last colon", () => {
    assert.strictEqual(portOf("127.0.0.1:5173"), 5173)
    assert.strictEqual(portOf("[::]:22"), 22)
    assert.strictEqual(portOf("127.0.0.53%lo:53"), 53)
    assert.strictEqual(hostOf("[::1]:631"), "[::1]")
    assert.strictEqual(portOf("garbage"), 0)
})

test("loopback is local, everything else is reachable", () => {
    for (const h of ["127.0.0.1", "127.0.0.53%lo", "::1", "[::1]"])
        assert.strictEqual(isExposed(h), false, h)
    for (const h of ["0.0.0.0", "[::]", "*", "192.168.1.5", "[fe80::1]"])
        assert.strictEqual(isExposed(h), true, h)
})

const rows = parse(text)
const find = (port, proto = "tcp") => rows.find(r => r.port === port && r.proto === proto)

test("IPv4 and IPv6 listeners of one service are one row", () => {
    assert.strictEqual(rows.filter(r => r.port === 3000).length, 1)
    assert.strictEqual(rows.filter(r => r.port === 22).length, 1)
})

test("a service is exposed if either family is", () => {
    assert.strictEqual(find(3000).exposed, true)
    assert.strictEqual(find(5173).exposed, false)
    assert.strictEqual(find(631).exposed, false)
    assert.strictEqual(find(53).exposed, false)
})

test("the owner is read, and missing when ss does not give it", () => {
    assert.strictEqual(find(5173).process, "node")
    assert.strictEqual(find(5173).pid, 1781)
    assert.strictEqual(find(22).process, "")
    assert.strictEqual(find(22).pid, 0)
})

test("live tcp connections are counted per port, not for udp", () => {
    assert.strictEqual(find(5173).conns, 2)
    assert.strictEqual(find(22).conns, 1)
    assert.strictEqual(find(5353, "udp").conns, 0)
})

test("exposed first, then by port", () => {
    const order = rows.map(r => (r.exposed ? "x" : "l") + r.port)
    assert.deepStrictEqual(order, ["x22", "x3000", "x5353", "x8080", "l53", "l631", "l5173"])
})

test("the address to copy", () => {
    assert.strictEqual(addressOf(find(3000)), "localhost:3000")
    assert.strictEqual(addressOf(find(5173)), "localhost:5173")
    assert.strictEqual(addressOf(find(8080)), "192.168.1.5:8080")
})

test("only tcp rows open in a browser", () => {
    assert.strictEqual(isWeb(find(3000)), true)
    assert.strictEqual(isWeb(find(5353, "udp")), false)
})

test("empty, garbage and ss missing give no rows", () => {
    assert.deepStrictEqual(parse(""), [])
    assert.deepStrictEqual(parse("\n===CONNECTIONS===\n"), [])
    assert.deepStrictEqual(parse("Netid State\nnot a line\n"), [])
})

process.exit(failures ? 1 : 0)
