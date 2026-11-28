import CoreGraphics

/// The Rows layout: windows in rows that share a top and a height, x free within a row — and
/// every window is in one: a drop anywhere joins the nearest row. Pure functions over
/// canvas coordinates (y down): no controller, no view, so every rule is unit-tested directly.
enum RowLayout {

    /// A window to lay out: `row` is which row it's in (nil = not yet placed — layout puts it in
    /// the row nearest its middle); `fixedHeight` keeps the
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
        /// The space between windows in a row.
        var gap: CGFloat
        /// The space between rows: wide enough that a row centred on screen leaves the rows
        /// beside it entirely off it, Dock strip included (see CanvasController.rowMetrics).
        var rowGap: CGFloat
        /// The canvas y of the first row's top.
        var top: CGFloat = 0
    }

    /// The vertical step from one row's top to the next's.
    static func pitch(_ m: Metrics) -> CGFloat { m.windowHeight + m.rowGap }

    /// Row `i`'s top edge.
    static func rowTop(_ i: Int, _ m: Metrics) -> CGFloat { m.top + CGFloat(i) * pitch(m) }

    /// The row index canvas y `y` falls in (negative above the first row).
    static func row(atY y: CGFloat, _ m: Metrics) -> Int {
        Int(((y - m.top) / pitch(m)).rounded(.down))
    }

    /// The row nearest canvas y `y` of `count` rows, measured to the rows' middles: anywhere in
    /// a row's band or the gap around it lands in it — only past halfway across the gap does it
    /// mean the next one.
    static func nearestRow(atY y: CGFloat, count: Int, _ m: Metrics) -> Int {
        min(max(Int(((y - m.top - m.windowHeight / 2) / pitch(m)).rounded()), 0), max(count - 1, 0))
    }

    /// Canonical positions. An unplaced item (row nil) joins the row nearest its middle — row 0
    /// when no rows exist yet. Rows: renumbered 0..<n keeping their order (empty rows vanish),
    /// each item at its row's top and height (fixedHeight ones keep theirs), sorted by minX —
    /// input order on ties — with at least `gap` between neighbours; x is otherwise kept.
    static func layout(_ items: [Item], _ m: Metrics) -> [Item] {
        var out = items
        let placed = Set(out.compactMap(\.row)).sorted()
        for i in out.indices where out[i].row == nil {
            out[i].row = placed.isEmpty ? 0 : placed[nearestRow(atY: out[i].frame.midY, count: placed.count, m)]
        }
        let used = Set(out.compactMap(\.row)).sorted()
        let renumber = Dictionary(uniqueKeysWithValues: used.enumerated().map { ($0.element, $0.offset) })
        let byRow = Dictionary(grouping: out.indices, by: { out[$0].row! })
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
        return out
    }

    /// The dragged item `id` was let go at `proposed` (the caller snapped it already). It joins
    /// the row nearest its middle — right of the row's end it extends the row — a new row opening
    /// above the first or below the last only when its middle is past them by half a pitch. Then
    /// everything settles (see layout). Left neighbours keep their x; the drop lands after the
    /// rightmost one it would overlap, and right neighbours are shoved on by the sweep.
    static func drop(_ id: CGWindowID, at proposed: CGRect, into items: [Item], _ m: Metrics) -> [Item] {
        guard let i = items.firstIndex(where: { $0.id == id }) else { return layout(items, m) }
        var out = items
        var k = Int(((proposed.midY - m.top - m.windowHeight / 2) / pitch(m)).rounded())
        let rowCount = Set(out.compactMap(\.row)).count
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
    /// the next one. Every band is a row, ordered by its top — a lone window is a row of one.
    /// x kept.
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
        var items: [Item] = []
        for (row, band) in bands.enumerated() {
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
}
