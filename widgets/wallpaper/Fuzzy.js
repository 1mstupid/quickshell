.pragma library

// Fuzzy matching for the wallpaper picker: the query's letters have to appear in the
// name in order, not next to each other ("mtncty" finds "mountain-city"). Matches in
// a row, at the start of a word and at the start of the name score higher, and a plain
// substring beats scattered letters. No QML types, so it can be tested with plain node.
// (The launcher only filters by substring, so there was nothing to reuse here.)

// -1 when the letters are not all there in order, otherwise higher is better
function score(name, query) {
    const n = String(name).toLowerCase()
    const q = String(query).toLowerCase().replace(/\s+/g, "")
    if (q === "")
        return 0

    let qi = 0
    let total = 0
    let last = -2
    let run = 0
    let first = -1
    for (let i = 0; i < n.length && qi < q.length; i++) {
        if (n.charAt(i) !== q.charAt(qi))
            continue
        let s = 1
        if (i === last + 1) {
            run++
            s += 2 * run
        } else {
            run = 0
        }
        if (i === 0 || /[^a-z0-9]/.test(n.charAt(i - 1)))
            s += 3
        total += s
        if (first < 0)
            first = i
        last = i
        qi++
    }
    if (qi < q.length)
        return -1

    const at = n.indexOf(q)
    if (at >= 0)
        total += at === 0 ? 15 : 10
    // earlier and shorter names first, as a tie-break
    return total - first * 0.05 - n.length * 0.01
}

// `items` that match `query`, best first; all of them, in order, for an empty query.
// `nameOf` turns an item into the text that is matched.
function rank(items, query, nameOf) {
    if (String(query).trim() === "")
        return items.slice()
    const hits = []
    for (let i = 0; i < items.length; i++) {
        const s = score(nameOf(items[i]), query)
        if (s >= 0)
            hits.push({ item: items[i], score: s, order: i })
    }
    hits.sort((a, b) => b.score - a.score || a.order - b.order)
    return hits.map(h => h.item)
}
