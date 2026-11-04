.pragma library

// Month calendar for the habits widget. Days are "YYYY-MM-DD" strings, like
// the rest of the habit data. No QML types, so it can be tested with plain node.

function key(d) {
    return d.getFullYear() + "-" + String(d.getMonth() + 1).padStart(2, "0")
        + "-" + String(d.getDate()).padStart(2, "0")
}

// The weeks covering the month of `day`, Monday first, as a flat list of
// { date, inMonth }, seven to a row. Days of the neighbouring months fill the
// first and last rows. Empty for an empty `day`.
function grid(day) {
    if (!day)
        return []
    const p = day.split("-").map(Number)
    const lead = (new Date(p[0], p[1] - 1, 1).getDay() + 6) % 7
    const days = new Date(p[0], p[1], 0).getDate()
    const cells = Math.ceil((lead + days) / 7) * 7
    const out = []
    for (let i = 0; i < cells; i++) {
        const d = new Date(p[0], p[1] - 1, 1 - lead + i)
        out.push({ date: key(d), inMonth: d.getMonth() === p[1] - 1 })
    }
    return out
}
