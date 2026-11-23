import CoreGraphics

/// The Rows layout: windows in rows that share a top and a height, x free within a row, plus an
/// "inbox" region to the rows' right for windows that aren't in one. Pure functions over
/// canvas coordinates (y down): no controller, no view, so every rule is unit-tested directly.
enum RowLayout {

    /// A window to lay out: `row` is which row it's in (nil = the inbox); `fixedHeight` keeps the
    /// window's own height, top-aligned in its row (a VM window sizing itself), where the rest
    /// take the row's window height.
    struct Item: Equatable {
        var id: CGWindowID
        var frame: CGRect
        var row: Int?
        var fixedHeight: Bool = false
    }

    /// What a layout is measured in.
    struct Metrics: Equatable {
        /// Every row's window height (the work area's height less the margins all round).
        var windowHeight: CGFloat
        /// The space between windows in a row, and between inbox items and shelves.
        var gap: CGFloat
        /// The space between rows: wide enough that a row centred on screen leaves the rows
        /// beside it entirely off it, Dock strip included (see CanvasController.rowMetrics).
        var rowGap: CGFloat
        /// The canvas y of the first row's top (and the inbox's).
        var top: CGFloat = 0
        /// The space between the rows' right end and the inbox region.
        var inboxGap: CGFloat
        /// A shelf wraps to the next once it would get wider than this.
        var inboxMaxWidth: CGFloat
    }

    /// The vertical step from one row's top to the next's.
    static func pitch(_ m: Metrics) -> CGFloat { m.windowHeight + m.rowGap }

    /// Row `i`'s top edge.
    static func rowTop(_ i: Int, _ m: Metrics) -> CGFloat { m.top + CGFloat(i) * pitch(m) }

    /// The row index canvas y `y` falls in (negative above the first row).
    static func row(atY y: CGFloat, _ m: Metrics) -> Int {
        Int(((y - m.top) / pitch(m)).rounded(.down))
    }

    /// Canonical positions. Rows: renumbered 0..<n keeping their order (empty rows vanish), each
    /// item at its row's top and height (fixedHeight ones keep theirs), sorted by minX — input
    /// order on ties — with at least `gap` between neighbours; x is otherwise kept. Inbox: packed
    /// on shelves starting at `inboxMinX`, ordered by (minY, minX), wrapping past `inboxMaxWidth`
    /// (a wider window gets its own shelf); shelf height = its tallest. Sizes unchanged there.
    static func layout(_ items: [Item], _ m: Metrics) -> [Item] {
        var out = items
        let used = Set(out.compactMap(\.row)).sorted()
        let renumber = Dictionary(uniqueKeysWithValues: used.enumerated().map { ($0.element, $0.offset) })
        let byRow = Dictionary(grouping: out.indices.filter { out[$0].row != nil }, by: { out[$0].row! })
        for (old, idxs) in byRow {
            guard let row = renumber[old] else { continue }
            var right = -CGFloat.infinity
            for i in sortedByMinX(idxs, out) {
                var f = out[i].frame
                f.origin.y = rowTop(row, m)
                if !out[i].fixedHeight { f.size.height = m.windowHeight }
                f.origin.x = max(f.minX, right + m.gap)
                out[i].frame = f
                out[i].row = row
                right = f.maxX
            }
        }
        // The inbox region to the right of every row.
        let inboxX = inboxMinX(out, excluding: nil, m)
        let inbox = sortedInbox(out.indices.filter { out[$0].row == nil }, out)
        var shelfTop = m.top, x = inboxX, shelfHeight: CGFloat = 0
        for i in inbox {
            var f = out[i].frame
            // A shelf that would run past inboxMaxWidth wraps; an item alone on one never does,
            // however wide it is.
            if x > inboxX, x + f.width - inboxX > m.inboxMaxWidth {
                shelfTop += shelfHeight + m.gap
                x = inboxX
                shelfHeight = 0
            }
            f.origin = CGPoint(x: x, y: shelfTop)
            out[i].frame = f
            x += f.width + m.gap
            shelfHeight = max(shelfHeight, f.height)
        }
        return out
    }

    /// The inbox region's left edge, computed without the item `excluding` (the dragged one: it
    /// hasn't landed yet). With no rows the inbox starts at the canvas's left plus `inboxGap`.
    static func inboxMinX(_ items: [Item], excluding: CGWindowID? = nil, _ m: Metrics) -> CGFloat {
        let right = items.lazy.filter { $0.id != excluding && $0.row != nil }.map(\.frame.maxX).max() ?? 0
        return right + m.inboxGap
    }

    /// The dragged item `id` was let go at `proposed` (the caller snapped it already). A middle at
    /// a row's height lands it in that row — right of the row's end it extends the row — a new
    /// row opening above the first or below the last when its middle is past them. Right of the
    /// rows' end at a height no row covers it's back in the inbox. Then everything settles (see
    /// layout). Left neighbours keep their x; the drop lands after the rightmost one it would
    /// overlap, and right neighbours are shoved on by the sweep.
    static func drop(_ id: CGWindowID, at proposed: CGRect, into items: [Item], _ m: Metrics) -> [Item] {
        guard let i = items.firstIndex(where: { $0.id == id }) else { return layout(items, m) }
        var out = items
        var k = row(atY: proposed.midY, m)
        let rowCount = Set(out.compactMap(\.row)).count
        let atRowHeight = k >= 0 && k < rowCount && proposed.midY < rowTop(k, m) + m.windowHeight
        if proposed.midX >= inboxMinX(out, excluding: id, m), !atRowHeight {
            out[i].row = nil
            out[i].frame.origin = proposed.origin
            return layout(out, m)
        }
        if k < 0 {
            // Dropped above the first row: a new one opens at the top.
            for j in out.indices where out[j].row != nil { out[j].row! += 1 }
            k = 0
        } else {
            // Below the last row: a new one opens there. Counting the dragged item's row too,
            // as the rows stand when it's let go.
            k = min(k, rowCount)
        }
        let left = out.filter { $0.id != id && $0.row == k && $0.frame.midX < proposed.midX }
            .map(\.frame.maxX).max()
        var f = proposed
        if let left { f.origin.x = max(f.minX, left + m.gap) }
        out[i].frame = f
        out[i].row = k
        return layout(out, m)
    }

    /// Free → Rows: windows that already form bands become rows. Sorted by top, each window joins
    /// the band when its vertical overlap with it is at least half the smaller height, else opens
    /// the next one. A band of two or more is a row, ordered by its top; a lone window goes to
    /// the inbox. x kept.
    static func distribute(_ frames: [(id: CGWindowID, frame: CGRect, fixedHeight: Bool)],
                           _ m: Metrics) -> [Item] {
        var bands: [(minY: CGFloat, maxY: CGFloat, members: [(id: CGWindowID, frame: CGRect, fixedHeight: Bool)])] = []
        for w in frames.sorted(by: { $0.frame.minY < $1.frame.minY }) {
            if let last = bands.last {
                let shared = min(last.maxY, w.frame.maxY) - max(last.minY, w.frame.minY)
                if shared >= min(last.maxY - last.minY, w.frame.height) / 2 {
                    bands[bands.count - 1].members.append(w)
                    bands[bands.count - 1].minY = min(last.minY, w.frame.minY)
                    bands[bands.count - 1].maxY = max(last.maxY, w.frame.maxY)
                    continue
                }
            }
            bands.append((w.frame.minY, w.frame.maxY, [w]))
        }
        var next = 0, items: [Item] = []
        for band in bands {
            let row = band.members.count >= 2 ? next : nil
            if row != nil { next += 1 }
            items += band.members.map { Item(id: $0.id, frame: $0.frame, row: row, fixedHeight: $0.fixedHeight) }
        }
        return layout(items, m)
    }

    /// Close the gap at canvas x `x` in `row`: every item starting at or right of it moves left
    /// until the first is `gap` from the item before it. Nothing to close (no item before or at
    /// the edge, or already tight) moves nothing.
    static func collapseGap(row: Int, after x: CGFloat, items: [Item], _ m: Metrics) -> [Item] {
        var out = items
        let idxs = sortedByMinX(out.indices.filter { out[$0].row == row }, out)
        guard let anchor = idxs.first(where: { out[$0].frame.minX >= x }),
              let before = idxs.last(where: { out[$0].frame.minX < x }) else { return layout(out, m) }
        let delta = out[before].frame.maxX + m.gap - out[anchor].frame.minX
        for i in idxs where out[i].frame.minX >= x { out[i].frame.origin.x += delta }
        return layout(out, m)
    }

    /// Every row gap-tight from its leftmost item (which keeps its x).
    static func collapseAll(_ items: [Item], _ m: Metrics) -> [Item] {
        var out = items
        let byRow = Dictionary(grouping: out.indices.filter { out[$0].row != nil }, by: { out[$0].row! })
        for (_, idxs) in byRow {
            let sorted = sortedByMinX(idxs, out)
            guard var right = sorted.first.map({ out[$0].frame.maxX }) else { continue }
            for i in sorted.dropFirst() {
                out[i].frame.origin.x = right + m.gap
                right = out[i].frame.maxX
            }
        }
        return layout(out, m)
    }

    /// Indices into `items` ordered by frame.minX, input order on ties.
    private static func sortedByMinX(_ idxs: [Int], _ items: [Item]) -> [Int] {
        idxs.sorted { items[$0].frame.minX == items[$1].frame.minX ? $0 < $1 : items[$0].frame.minX < items[$1].frame.minX }
    }

    /// Indices into `items` ordered by (minY, minX), input order on ties.
    private static func sortedInbox(_ idxs: [Int], _ items: [Item]) -> [Int] {
        idxs.sorted {
            let a = items[$0].frame, b = items[$1].frame
            if a.minY != b.minY { return a.minY < b.minY }
            if a.minX != b.minX { return a.minX < b.minX }
            return $0 < $1
        }
    }
}
