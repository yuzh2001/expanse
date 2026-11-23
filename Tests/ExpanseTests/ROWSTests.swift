import Testing
import CoreGraphics
@_private(sourceFile: "RowLayout.swift") @testable import Expanse

/// docs/regression/rows.md. The Rows layout engine, pure functions over canvas frames — no
/// controller, no screen. The metrics below: 400pt rows with the 20pt gap, the grid a 60pt gap
/// to the rows' right wrapping past 500pt.
@Suite("ROWS: Rows layout", .serialized) struct ROWSTests {

    // MARK: Helpers

    private static let m = RowLayout.Metrics(windowHeight: 400, gap: 20, gridGap: 60, gridMaxWidth: 500)

    private static func r(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat) -> CGRect {
        CGRect(x: x, y: y, width: w, height: h)
    }

    private static func i(_ id: CGWindowID, _ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat,
                          row: Int?, fixed: Bool = false) -> RowLayout.Item {
        RowLayout.Item(id: id, frame: r(x, y, w, h), row: row, fixedHeight: fixed)
    }

    private static func frame(_ laid: [RowLayout.Item], _ id: CGWindowID) -> CGRect {
        laid.first { $0.id == id }!.frame
    }

    // MARK: ROWS-01

    @Test("ROWS-01 A row shares its top and height, in x order with the gap kept (logic)")
    func rows01a() {
        // Row 3's windows out of order and overlapping; row 7 renumbers to 1 (empty rows vanish).
        let laid = RowLayout.layout([
            Self.i(1, 200, 50, 300, 600, row: 3),
            Self.i(2, 100, 99, 300, 300, row: 3),
            Self.i(3, 0, 900, 250, 200, row: 7),
        ], Self.m)
        // Sorted by minX: 2 stays at 100; 1's x would overlap, so it goes after it, a gap apart.
        #expect(Self.frame(laid, 2) == Self.r(100, 0, 300, 400))
        #expect(Self.frame(laid, 1) == Self.r(420, 0, 300, 400))
        // Row 7 becomes row 1, its top 400 + the gap; same height.
        #expect(Self.frame(laid, 3) == Self.r(0, 420, 250, 400))
    }

    @Test("ROWS-01 A window its app sizes keeps its height, top-aligned in the row (logic)")
    func rows01b() {
        let laid = RowLayout.layout([
            Self.i(1, 0, 30, 300, 200, row: 0),
            Self.i(2, 400, 60, 300, 900, row: 0, fixed: true),
        ], Self.m)
        #expect(Self.frame(laid, 1) == Self.r(0, 0, 300, 400))
        #expect(Self.frame(laid, 2) == Self.r(400, 0, 300, 900))
    }

    // MARK: ROWS-02

    @Test("ROWS-02 The grid sits right of the rows and packs on shelves that wrap (logic)")
    func rows02() {
        let laid = RowLayout.layout([
            Self.i(1, 0, 0, 400, 300, row: 0),          // rows end at x 400; grid starts at 460
            Self.i(2, 0, 0, 200, 200, row: nil),
            Self.i(3, 0, 0, 200, 200, row: nil),
            Self.i(4, 0, 0, 600, 100, row: nil),        // wider than a shelf alone
            Self.i(5, 0, 0, 100, 100, row: nil),
        ], Self.m)
        // Shelf one: 2 and 3 side by side (200 + 20 + 200 = 420 fits 500). 4 is wider than a
        // shelf, so it gets one to itself, then 5 wraps under it.
        #expect(Self.frame(laid, 2) == Self.r(460, 0, 200, 200))
        #expect(Self.frame(laid, 3) == Self.r(680, 0, 200, 200))
        #expect(Self.frame(laid, 4) == Self.r(460, 220, 600, 100))
        #expect(Self.frame(laid, 5) == Self.r(460, 340, 100, 100))
        // Ordered by (minY, minX): one drawn low on the canvas packs no sooner than the others.
        let reordered = RowLayout.layout([
            Self.i(1, 0, 0, 400, 300, row: 0),
            Self.i(2, 0, 500, 200, 200, row: nil),
            Self.i(3, 0, 50, 200, 200, row: nil),
        ], Self.m)
        #expect(Self.frame(reordered, 3) == Self.r(460, 0, 200, 200))
        #expect(Self.frame(reordered, 2) == Self.r(680, 0, 200, 200))
    }

    // MARK: ROWS-03

    @Test("ROWS-03 Laying out an already laid-out set changes nothing (logic)")
    func rows03() {
        let items = [
            Self.i(1, 200, 50, 300, 600, row: 3),
            Self.i(2, 100, 99, 300, 300, row: 3),
            Self.i(3, 0, 900, 250, 200, row: 7),
            Self.i(4, 0, 0, 200, 200, row: nil),
            Self.i(5, 0, 40, 200, 200, row: nil),
        ]
        let once = RowLayout.layout(items, Self.m)
        #expect(RowLayout.layout(once, Self.m) == once)
    }

    // MARK: ROWS-04

    @Test("ROWS-04 Dropping into the middle of a row shoves the windows to its right (logic)")
    func rows04a() {
        let items = [Self.i(1, 0, 0, 300, 400, row: 0), Self.i(2, 340, 0, 300, 400, row: 0),
                     Self.i(3, 2000, 0, 200, 400, row: nil)]
        // Between them (its middle right of 1's, left of 2's): it lands after 1, 2 shifts over.
        let laid = RowLayout.drop(3, at: Self.r(150, 0, 200, 400), into: items, Self.m)
        #expect(Self.frame(laid, 1) == Self.r(0, 0, 300, 400))
        #expect(Self.frame(laid, 3) == Self.r(320, 0, 200, 400))
        #expect(Self.frame(laid, 2) == Self.r(540, 0, 300, 400))
    }

    @Test("ROWS-04 Dropping over a window's left end lands right after it (logic)")
    func rows04b() {
        let items = [Self.i(1, 0, 0, 300, 400, row: 0), Self.i(2, 340, 0, 300, 400, row: 0),
                     Self.i(3, 2000, 0, 200, 400, row: nil)]
        // Its left edge is over 1 (250 < 300) but its middle is right of 1's: after it.
        let laid = RowLayout.drop(3, at: Self.r(250, 0, 200, 400), into: items, Self.m)
        #expect(Self.frame(laid, 3) == Self.r(320, 0, 200, 400))
        #expect(Self.frame(laid, 2) == Self.r(540, 0, 300, 400))
    }

    // MARK: ROWS-05

    @Test("ROWS-05 Dropping past the rows opens a new row; into the grid region puts it back (logic)")
    func rows05() {
        let rows = [Self.i(1, 0, 0, 300, 400, row: 0), Self.i(2, 0, 420, 300, 400, row: 1)]
        // Above the first row: a new row 0, the others move down.
        var laid = RowLayout.drop(3, at: Self.r(0, -400, 200, 400),
                                  into: rows + [Self.i(3, 2000, 0, 200, 400, row: nil)], Self.m)
        #expect(laid.first { $0.id == 3 }!.row == 0)
        #expect(Self.frame(laid, 3) == Self.r(0, 0, 200, 400))
        #expect(Self.frame(laid, 1) == Self.r(0, 420, 300, 400))
        #expect(Self.frame(laid, 2) == Self.r(0, 840, 300, 400))
        // Below the last: a new row there.
        laid = RowLayout.drop(4, at: Self.r(50, 900, 200, 400),
                              into: rows + [Self.i(4, 2000, 0, 200, 400, row: nil)], Self.m)
        #expect(laid.first { $0.id == 4 }!.row == 2)
        #expect(Self.frame(laid, 4) == Self.r(50, 840, 200, 400))
        // Right of the rows' end (they end at 300, the grid starts at 360): back to the grid,
        // packed at the grid's start at its own size whatever the drop's spot was.
        laid = RowLayout.drop(5, at: Self.r(600, 100, 250, 150),
                              into: rows + [Self.i(5, 50, 420, 250, 400, row: 1)], Self.m)
        #expect(laid.first { $0.id == 5 }!.row == nil)
        #expect(Self.frame(laid, 5) == Self.r(360, 0, 250, 400))
    }

    // MARK: ROWS-06

    @Test("ROWS-06 Switching to Rows: windows already in bands go into rows, strays to the grid (logic)")
    func rows06() {
        let laid = RowLayout.distribute([
            (id: 1, frame: Self.r(0, 100, 600, 400), fixedHeight: false),
            (id: 2, frame: Self.r(700, 120, 600, 380), fixedHeight: false),
            (id: 3, frame: Self.r(1400, 105, 600, 400), fixedHeight: false),
            (id: 4, frame: Self.r(0, 600, 600, 400), fixedHeight: false),
            (id: 5, frame: Self.r(700, 620, 600, 400), fixedHeight: false),
            (id: 6, frame: Self.r(400, 1200, 600, 400), fixedHeight: false),
        ], Self.m)
        // The two bands (y ~100 and y ~600) are rows 0 and 1; the lone window at y 1200 is grid.
        #expect(laid.first { $0.id == 1 }!.row == 0 && laid.first { $0.id == 3 }!.row == 0)
        #expect(laid.first { $0.id == 4 }!.row == 1 && laid.first { $0.id == 5 }!.row == 1)
        #expect(laid.first { $0.id == 6 }!.row == nil)
        // x is kept where there's no overlap; tops are the rows'.
        #expect(Self.frame(laid, 3) == Self.r(1400, 0, 600, 400))
        #expect(Self.frame(laid, 5) == Self.r(700, 420, 600, 400))
        // The grid goes right of the widest row (2000) + the grid gap.
        #expect(Self.frame(laid, 6) == Self.r(2060, 0, 600, 400))
    }

    // MARK: ROWS-07

    @Test("ROWS-07 A gap in a row collapses leftwards; everything collapses to gap-tight (logic)")
    func rows07() {
        let items = [
            Self.i(1, 0, 0, 300, 400, row: 0),
            Self.i(2, 500, 0, 300, 400, row: 0),
            Self.i(3, 900, 0, 300, 400, row: 0),
        ]
        // Click the gap after 1 (before 2): 2 and everything right of it shifts till gap-tight.
        var laid = RowLayout.collapseGap(row: 0, after: 450, items: items, Self.m)
        #expect(Self.frame(laid, 1) == Self.r(0, 0, 300, 400))
        #expect(Self.frame(laid, 2) == Self.r(320, 0, 300, 400))
        #expect(Self.frame(laid, 3) == Self.r(720, 0, 300, 400))
        // Already tight, or the edge before the first window: nothing moves.
        let tight = RowLayout.collapseGap(row: 0, after: 450, items: laid, Self.m)
        #expect(Self.frame(tight, 2) == Self.r(320, 0, 300, 400))
        laid = RowLayout.collapseGap(row: 0, after: -50, items: items, Self.m)
        #expect(Self.frame(laid, 1) == Self.r(0, 0, 300, 400))
        #expect(Self.frame(laid, 2) == Self.r(500, 0, 300, 400))
        // And the whole row at once: gap-tight from its leftmost.
        laid = RowLayout.collapseAll(items, Self.m)
        #expect(Self.frame(laid, 2) == Self.r(320, 0, 300, 400))
        #expect(Self.frame(laid, 3) == Self.r(640, 0, 300, 400))
    }
}
