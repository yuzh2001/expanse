import Testing
import AppKit
import ScreenCaptureKit
@_private(sourceFile: "RowLayout.swift") @testable import Expanse
@_private(sourceFile: "CanvasController.swift") @testable import Expanse
@_private(sourceFile: "ManagedWindow.swift") @testable import Expanse
@_private(sourceFile: "LayoutStore.swift") @testable import Expanse

/// docs/regression/rows.md. The Rows layout engine, pure functions over canvas frames — no
/// controller, no screen. The metrics below: 400pt rows 100pt apart with a 20pt gap, the inbox
/// a 60pt gap to the rows' right wrapping past 500pt.
@MainActor @Suite("ROWS: Rows layout", .serialized) struct ROWSTests {

    // MARK: Helpers

    private static let m = RowLayout.Metrics(windowHeight: 400, gap: 20, rowGap: 100,
                                             inboxGap: 60, inboxMaxWidth: 500)

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
        // Row 7 becomes row 1, its top the row pitch (400 + 100 between rows); same height.
        #expect(Self.frame(laid, 3) == Self.r(0, 500, 250, 400))
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

    @Test("ROWS-02 The inbox sits right of the rows and packs on shelves that wrap (logic)")
    func rows02() {
        let laid = RowLayout.layout([
            Self.i(1, 0, 0, 400, 300, row: 0),          // rows end at x 400; inbox starts at 460
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

    @Test("ROWS-05 Dropping past the rows opens a new row; into the inbox region puts it back (logic)")
    func rows05() {
        let rows = [Self.i(1, 0, 0, 300, 400, row: 0), Self.i(2, 0, 420, 300, 400, row: 1)]
        // Above the first row: a new row 0, the others move down.
        var laid = RowLayout.drop(3, at: Self.r(0, -400, 200, 400),
                                  into: rows + [Self.i(3, 2000, 0, 200, 400, row: nil)], Self.m)
        #expect(laid.first { $0.id == 3 }!.row == 0)
        #expect(Self.frame(laid, 3) == Self.r(0, 0, 200, 400))
        #expect(Self.frame(laid, 1) == Self.r(0, 500, 300, 400))
        #expect(Self.frame(laid, 2) == Self.r(0, 1000, 300, 400))
        // Below the last: a new row there.
        laid = RowLayout.drop(4, at: Self.r(50, 900, 200, 400),
                              into: rows + [Self.i(4, 2000, 0, 200, 400, row: nil)], Self.m)
        #expect(laid.first { $0.id == 4 }!.row == 2)
        #expect(Self.frame(laid, 4) == Self.r(50, 1000, 200, 400))
        // Right of the rows' end (they end at 300, the inbox starts at 360) but at a row's
        // height (its middle 175 is in row 0's band): it extends row 0, not the inbox.
        laid = RowLayout.drop(5, at: Self.r(600, 100, 250, 150),
                              into: rows + [Self.i(5, 50, 420, 250, 400, row: 1)], Self.m)
        #expect(laid.first { $0.id == 5 }!.row == 0)
        #expect(Self.frame(laid, 5) == Self.r(600, 0, 250, 400))
        // Same spot past the rows' end but let go in the gap between rows (its middle 480 is
        // under row 0's bottom at 400): back to the inbox, packed at its start at its own size.
        laid = RowLayout.drop(6, at: Self.r(600, 405, 250, 150),
                              into: rows + [Self.i(6, 50, 420, 250, 400, row: 1)], Self.m)
        #expect(laid.first { $0.id == 6 }!.row == nil)
        #expect(Self.frame(laid, 6) == Self.r(360, 0, 250, 400))
    }

    // MARK: ROWS-06

    @Test("ROWS-06 Switching to Rows: windows already in bands go into rows, strays to the inbox (logic)")
    func rows06() {
        let laid = RowLayout.distribute([
            (id: 1, frame: Self.r(0, 100, 600, 400), fixedHeight: false),
            (id: 2, frame: Self.r(700, 120, 600, 380), fixedHeight: false),
            (id: 3, frame: Self.r(1400, 105, 600, 400), fixedHeight: false),
            (id: 4, frame: Self.r(0, 600, 600, 400), fixedHeight: false),
            (id: 5, frame: Self.r(700, 620, 600, 400), fixedHeight: false),
            (id: 6, frame: Self.r(400, 1200, 600, 400), fixedHeight: false),
        ], Self.m)
        // The two bands (y ~100 and y ~600) are rows 0 and 1; the lone window at y 1200 is inbox.
        #expect(laid.first { $0.id == 1 }!.row == 0 && laid.first { $0.id == 3 }!.row == 0)
        #expect(laid.first { $0.id == 4 }!.row == 1 && laid.first { $0.id == 5 }!.row == 1)
        #expect(laid.first { $0.id == 6 }!.row == nil)
        // x is kept where there's no overlap; tops are the rows'.
        #expect(Self.frame(laid, 3) == Self.r(1400, 0, 600, 400))
        #expect(Self.frame(laid, 5) == Self.r(700, 500, 600, 400))
        // The inbox goes right of the widest row (2000) + the inbox gap.
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

    // MARK: Wired into the canvas (fake windows, no real ones move)

    /// A window on the canvas where Expanse last put it, so a scan doesn't follow anything.
    private static func placed(_ id: CGWindowID, canvas: CGRect, pid: pid_t = Fake.firstPID) -> ManagedWindow {
        let real = canvas.offsetBy(dx: 0, dy: TestDisplay.laptop.menuBar)
        let w = Fake.window(id: id, pid: pid, canvas: canvas, real: real)
        w.lastPlaced = real.origin
        return w
    }

    /// One window scan, as PLACETests does it: `standard` the new windows Accessibility calls
    /// standard document windows.
    private static func scan(_ c: CanvasController, _ scWindows: [SCWindow], standard: [CGWindowID] = []) {
        var ax = CanvasController.AXSnapshot()
        for id in standard {
            ax.standard.insert(id)
            ax.known.insert(id)
            c.windowKinds[id] = CanvasController.WindowKind(standard: true, at: CACurrentMediaTime())
        }
        c.apply(scWindows, ax: ax, stale: false)
    }

    private static func window(_ c: CanvasController, _ id: CGWindowID) -> ManagedWindow? {
        c.windows.first { $0.id == id }
    }

    /// A laptop with a 60pt Dock at the bottom: the work area is 889pt, a row's height 857pt.
    /// 60pt out of view below the work area puts the rows 124pt apart, the second's top 981pt —
    /// a centred row's neighbours clear the screen, Dock strip included (see rowMetrics).
    private static let docked = TestDisplay(dockBottom: 60)

    /// Leaves the canvas inert and Rows mode off, so nothing leaks into another test.
    private static func finish(_ c: CanvasController) {
        [c.saveWork, c.syncSoonWork, c.recheckWork].forEach { $0?.cancel() }
        c.cancelAnimation()
        c.snapshotTimer?.invalidate()
        c.isPaused = true
        UserDefaults.standard.removeObject(forKey: CanvasController.rowsModeKey)
    }

    // MARK: ROWS-08

    @Test("ROWS-08 Turning Arrange in rows on lays bands out as rows at the work area's height")
    func rows08() {
        defer { UserDefaults.standard.removeObject(forKey: CanvasController.rowsModeKey) }
        let c = TestCanvas.make(display: Self.docked, windows: [
            Self.placed(1, canvas: Self.r(0, 100, 600, 400)),
            Self.placed(2, canvas: Self.r(700, 110, 600, 390)),
            Self.placed(3, canvas: Self.r(1400, 100, 600, 400)),
            Self.placed(4, canvas: Self.r(0, 600, 600, 400)),
            Self.placed(5, canvas: Self.r(700, 600, 600, 400)),
            Self.placed(6, canvas: Self.r(400, 1400, 600, 400)),
        ])
        defer { Self.finish(c) }
        #expect(c.workArea.height == 889)
        c.rowsMode = true
        // Two bands of aligned windows become rows 0 and 1, sized to the work area's height.
        for w in c.windows where [1, 2, 3].contains(w.id) {
            #expect(w.row == 0 && w.canvasFrame.minY == 0 && w.canvasFrame.height == 857, "\(w.id)")
        }
        #expect(c.windows[0].canvasFrame.origin == .zero && c.windows[1].canvasFrame.origin == CGPoint(x: 700, y: 0))
        #expect(Self.window(c, 4)!.row == 1 && Self.window(c, 4)!.canvasFrame == Self.r(0, 981, 600, 857))
        // The stray joins the inbox: its own size, packed right of the rows' end (2000 + 200).
        let stray = Self.window(c, 6)!
        #expect(stray.row == nil && stray.canvasFrame == Self.r(2200, 0, 600, 400))
    }

    // MARK: ROWS-09

    @Test("ROWS-09 A new window opens in the inbox, beside the rows")
    func rows09() {
        defer { UserDefaults.standard.removeObject(forKey: CanvasController.rowsModeKey) }
        let a = Self.placed(1, canvas: Self.r(0, 100, 600, 400))
        let b = Self.placed(2, canvas: Self.r(700, 100, 600, 400))
        let c = TestCanvas.make(display: Self.docked, windows: [a, b])
        defer { Self.finish(c) }
        c.firstSync = false
        c.snapshotTimer = Timer(timeInterval: 3600, repeats: false) { _ in }
        c.rowsMode = true
        // A window opens where its app put it (below the rows, say): the inbox takes it.
        let n = Fake.scWindow(id: 3, pid: Fake.firstPID, bundleID: "com.example.app", appName: "Example",
                              frame: CGRect(x: 300, y: 200, width: 500, height: 300))
        Self.scan(c, [a.scWindow, b.scWindow, n], standard: [3])
        let w = Self.window(c, 3)!
        #expect(w.row == nil)
        // Right of the rows' end (1300) plus the inbox gap (200), at its own size.
        #expect(w.canvasFrame == Self.r(1500, 0, 500, 300))
    }

    // MARK: ROWS-10

    @Test("ROWS-10 A canvas drop lands in the row its middle's in, or back in the inbox")
    func rows10() {
        defer { UserDefaults.standard.removeObject(forKey: CanvasController.rowsModeKey) }
        let c = TestCanvas.make(display: Self.docked, windows: [
            Self.placed(1, canvas: Self.r(0, 0, 600, 857)),
            Self.placed(2, canvas: Self.r(620, 0, 600, 857)),
            Self.placed(3, canvas: Self.r(0, 981, 600, 857)),
            Self.placed(4, canvas: Self.r(620, 981, 600, 857)),
        ])
        defer { Self.finish(c) }
        c.rowsMode = true
        // 1 let go with its middle in row 1, over 3's right end: after 3, and 4 shoved right.
        c.rowsDrop(Self.window(c, 1)!, at: Self.r(150, 900, 600, 857))
        #expect(Self.window(c, 1)!.row == 1 && Self.window(c, 1)!.canvasFrame == Self.r(620, 981, 600, 857))
        #expect(Self.window(c, 4)!.canvasFrame == Self.r(1240, 981, 600, 857))
        // 3 let go right of the rows (they end at 1840, the inbox starts at 2040) in the gap
        // between them (its middle 908.5 is under row 0's bottom at 857): the inbox.
        c.rowsDrop(Self.window(c, 3)!, at: Self.r(2100, 480, 600, 857))
        #expect(Self.window(c, 3)!.row == nil && Self.window(c, 3)!.canvasFrame == Self.r(2040, 0, 600, 857))
        // Let go just as far right but at row 1's height: it joins row 1 where dropped.
        c.rowsDrop(Self.window(c, 3)!, at: Self.r(2100, 981, 600, 857))
        #expect(Self.window(c, 3)!.row == 1 && Self.window(c, 3)!.canvasFrame == Self.r(2100, 981, 600, 857))
    }

    // MARK: ROWS-11

    @Test("ROWS-11 A display change re-lays the rows at the new work area's height, keeping x")
    func rows11() {
        defer { UserDefaults.standard.removeObject(forKey: CanvasController.rowsModeKey) }
        let c = TestCanvas.make(display: Self.docked, windows: [
            Self.placed(1, canvas: Self.r(0, 0, 600, 857)),
            Self.placed(2, canvas: Self.r(620, 0, 600, 857)),
        ])
        defer { Self.finish(c) }
        c.rowsMode = true
        // To the plain laptop: the work area is 949pt, so the row's height becomes 917.
        c.displayOverride = (TestDisplay.laptop.frame, TestDisplay.laptop.usable)
        c.updateOverlayFrame()
        c.refit(tidy: false, rederiving: [])
        #expect(Self.window(c, 1)!.canvasFrame == Self.r(0, 0, 600, 917))
        #expect(Self.window(c, 2)!.canvasFrame == Self.r(620, 0, 600, 917))
    }

    // MARK: ROWS-12

    @Test("ROWS-12 A window's row survives a layout save and load")
    func rows12() throws {
        defer { UserDefaults.standard.removeObject(forKey: CanvasController.rowsModeKey) }
        let w = Self.placed(1, canvas: Self.r(0, 0, 600, 857))
        w.row = 1
        let c = TestCanvas.make(display: Self.docked, windows: [w])
        defer { Self.finish(c) }
        let e = c.savedEntry(w)
        #expect(e.row == 1)
        // Through the file and back: the spot a window takes comes with its row.
        LayoutStore.save(SavedLayout.with([e]))
        let loaded = try #require(LayoutStore.load()?.windows.first)
        #expect(loaded.row == 1)
        let back = Fake.window(id: 1, canvas: .zero)
        c.takeSpot(back, loaded, actual: CGRect(x: 100, y: 33, width: 600, height: 857))
        #expect(back.row == 1)
        // And a layout saved before rows: no row.
        let old = try JSONDecoder().decode(SavedLayout.Window.self,
                                           from: #"{"bundleID":"b","appName":"a","title":"t","x":0,"y":0}"#.data(using: .utf8)!)
        #expect(old.row == nil)
    }

    // MARK: ROWS-13

    @Test("ROWS-13 Dragging on the canvas snaps sideways only")
    func rows13() {
        let a = Fake.window(id: 1, canvas: Self.r(0, 0, 600, 400))
        let c = TestCanvas.make(windows: [a])
        defer { Self.finish(c) }
        // In Rows mode the row a drop lands in is the drag's middle: x snaps, y stays free.
        let (f, _) = c.snap(Self.r(627, 300, 400, 300), excluding: [2], yToo: false)
        #expect(f == Self.r(620, 300, 400, 300))
        let (top, lines) = c.snap(Self.r(620, 6, 400, 300), excluding: [2], yToo: false)
        #expect(top.minY == 6, "no top-edge snap, but it still snaps sideways")
        #expect(lines.isEmpty)
    }

    // MARK: ROWS-14

    @Test("ROWS-14 With Arrange in rows off, nothing about the free layout changes")
    func rows14() {
        defer { UserDefaults.standard.removeObject(forKey: CanvasController.rowsModeKey) }
        let a = Fake.window(id: 1, canvas: Self.r(0, 0, 600, 400))
        let c = TestCanvas.make(windows: [a])
        defer { Self.finish(c) }
        #expect(!c.rowsMode)
        // A canvas drop just notes the move, as ever (see rowsDrop's guard).
        let w = Self.window(c, 1)!
        c.rowsDrop(w, at: Self.r(50, 60, 600, 400))
        #expect(w.canvasFrame == Self.r(0, 0, 600, 400) && w.row == nil)
        c.applyRows()
        #expect(w.canvasFrame == Self.r(0, 0, 600, 400))
        // And snapping still works in both directions.
        let (f, _) = c.snap(Self.r(627, 6, 400, 300), excluding: [2])
        #expect(f.minY == 0 && f.minX == 620)
    }

    // MARK: ROWS-15

    @Test("ROWS-15 A centred row keeps the rows beside it off the screen, Dock strip included")
    func rows15() {
        defer { UserDefaults.standard.removeObject(forKey: CanvasController.rowsModeKey) }
        let c = TestCanvas.make(display: Self.docked, windows: [
            Self.placed(1, canvas: Self.r(0, 0, 600, 400)),
            Self.placed(2, canvas: Self.r(700, 0, 600, 400)),
            Self.placed(3, canvas: Self.r(0, 981, 600, 400)),
            Self.placed(4, canvas: Self.r(700, 981, 600, 400)),
            Self.placed(5, canvas: Self.r(0, 1962, 600, 400)),
            Self.placed(6, canvas: Self.r(700, 1962, 600, 400)),
        ])
        defer { Self.finish(c) }
        c.rowsMode = true
        // Rows a viewport and more apart: pitch = 857 + max(96, 60 out of view + 16 + 48).
        #expect(RowLayout.pitch(c.rowMetrics) == 981)
        // Centre the middle row: the ones beside it are wholly off the screen — nothing of them
        // shows beside or behind the Dock — so they stay parked pictures on the backdrop.
        c.camera = c.focusCamera(for: Self.window(c, 3)!)
        let parked = Dictionary(uniqueKeysWithValues: c.commitPlan().map { ($0.0.id, $0.2) })
        #expect(parked[3] == false && parked[4] == false)
        for id in [1, 2, 5, 6] as [CGWindowID] {
            #expect(parked[id] == true, "\(id)")
            let r = c.camera.toView(Self.window(c, id)!.canvasFrame)
                .offsetBy(dx: c.viewport.minX, dy: c.viewport.minY)
            #expect(r.intersection(c.viewport).isNull, "\(id) at \(r)")
        }
    }
}
