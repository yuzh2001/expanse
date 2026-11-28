import Testing
import AppKit
import ScreenCaptureKit
@_private(sourceFile: "WindowRules.swift") @testable import Expanse
@_private(sourceFile: "CanvasController.swift") @testable import Expanse
@_private(sourceFile: "ManagedWindow.swift") @testable import Expanse
@_private(sourceFile: "RowLayout.swift") @testable import Expanse

/// docs/regression/floating.md. Floating windows: rule-matched utilities that open over what
/// you're doing, held out of the layout until a managed window takes focus — then the rows.
@MainActor @Suite("FLOAT: Floating windows", .serialized) struct FLOATTests {

    // MARK: Helpers

    private static let rules = [
        FloatRule(bundleID: "com.example.calc", appName: "Calc"),
        FloatRule(bundleID: "com.example.chat", appName: "Chat", nonMainOnly: true),
        FloatRule(bundleID: "com.example.shots", appName: "Shots", titlePattern: "^Shot"),
        FloatRule(bundleID: "com.example.off", appName: "Off", enabled: false),
    ]

    /// The test rules stand in for the built-in table.
    private static func withRules<T>(_ body: () throws -> T) rethrows -> T {
        let data = try! JSONEncoder().encode(rules)
        return try Env.withDefaults([WindowRules.rulesKey: data], body)
    }

    /// A window on the canvas where Expanse last put it (see ROWSTests.placed).
    private static func placed(_ id: CGWindowID, canvas: CGRect, pid: pid_t = Fake.firstPID) -> ManagedWindow {
        let real = canvas.offsetBy(dx: 0, dy: TestDisplay.laptop.menuBar)
        let w = Fake.window(id: id, pid: pid, canvas: canvas, real: real)
        w.lastPlaced = real.origin
        return w
    }

    private static func r(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat) -> CGRect {
        CGRect(x: x, y: y, width: w, height: h)
    }

    /// One window scan (see ROWSTests.scan): `standard` the windows Accessibility calls standard.
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

    /// A rows-mode canvas with two rowed windows and the test rules in place.
    private static func rowsCanvas() -> CanvasController {
        let c = TestCanvas.make(display: .laptop, windows: [
            placed(1, canvas: r(0, 100, 600, 400)), placed(2, canvas: r(700, 100, 600, 400)),
        ])
        c.firstSync = false
        c.snapshotTimer = Timer(timeInterval: 3600, repeats: false) { _ in }
        c.rowsMode = true
        return c
    }

    /// Leaves the canvas inert and the rules back at the built-in table.
    private static func finish(_ c: CanvasController) {
        [c.saveWork, c.syncSoonWork, c.recheckWork, c.focusSettleWork].forEach { $0?.cancel() }
        c.cancelAnimation()
        c.snapshotTimer?.invalidate()
        c.isPaused = true
        UserDefaults.standard.removeObject(forKey: CanvasController.rowsModeKey)
        UserDefaults.standard.removeObject(forKey: WindowRules.rulesKey)
    }

    // MARK: FLOAT-01

    @Test("FLOAT-01 A rule matches by app, then title, and non-main only with a sibling (logic)")
    func float01() {
        let floats = { WindowRules.floats(bundleID: $0, title: $1, hasSibling: $2, rules: Self.rules) }
        #expect(floats("com.example.calc", "Calculator", false))
        #expect(!floats("com.example.editor", "Readme", true))
        // nonMainOnly: the app's first window counts as its main one; the next floats.
        #expect(!floats("com.example.chat", "Chat", false))
        #expect(floats("com.example.chat", "图片和视频", true))
        // A title pattern narrows a rule to that app's matching windows.
        #expect(floats("com.example.shots", "Shot 2026-01-01", false))
        #expect(!floats("com.example.shots", "Settings", false))
        // A disabled rule matches nothing.
        #expect(!floats("com.example.off", "Anything", true))
    }

    // MARK: FLOAT-02

    @Test("FLOAT-02 A rule-matched new window floats where it opened, out of the layout")
    func float02() {
        Self.withRules {
            let c = Self.rowsCanvas()
            defer { Self.finish(c) }
            // Calc's new window opens over your work (below the rows, say): it floats — kept out
            // of the rows and out of every plan to move real windows.
            let n = Fake.scWindow(id: 3, pid: Fake.firstPID, bundleID: "com.example.calc", appName: "Calc",
                                  frame: CGRect(x: 300, y: 700, width: 320, height: 480))
            Self.scan(c, [c.windows[0].scWindow, c.windows[1].scWindow, n], standard: [3])
            let w = Self.window(c, 3)!
            #expect(w.floating && w.row == nil)
            #expect(w.canvasFrame.origin == CGPoint(x: 300, y: 700 - TestDisplay.laptop.menuBar))
            #expect(w.returnTo != nil)
            #expect(!c.commitPlan().contains { $0.0 === w })
            // The next un-matched window joins the row you're working in at its right end
            // (row 0 ends at 1300, a gap later 1320), at the row's top and height (laptop: 917).
            let m = Fake.scWindow(id: 4, pid: Fake.firstPID, bundleID: "com.example.app", appName: "Example",
                                  frame: CGRect(x: 300, y: 200, width: 500, height: 300))
            Self.scan(c, [c.windows[0].scWindow, c.windows[1].scWindow, n, m], standard: [4])
            let u = Self.window(c, 4)!
            #expect(!u.floating && u.row == 0 && u.canvasFrame == Self.r(1320, 0, 500, 917))
        }
    }

    // MARK: FLOAT-03

    @Test("FLOAT-03 Focusing a managed window sweeps every floater into the rows")
    func float03() {
        Self.withRules {
            let c = Self.rowsCanvas()
            defer { Self.finish(c) }
            let n = Fake.scWindow(id: 3, pid: Fake.firstPID, bundleID: "com.example.calc", appName: "Calc",
                                  frame: CGRect(x: 300, y: 700, width: 320, height: 480))
            let m = Fake.scWindow(id: 4, pid: Fake.firstPID, bundleID: "com.example.calc", appName: "Calc",
                                  frame: CGRect(x: 500, y: 300, width: 320, height: 480))
            Self.scan(c, [c.windows[0].scWindow, c.windows[1].scWindow, n, m], standard: [3, 4])
            #expect(Self.window(c, 3)!.floating && Self.window(c, 4)!.floating)
            // Focusing one of them changes nothing; focusing a managed window sweeps them both.
            c.focusSettled(on: 4)
            #expect(Self.window(c, 3)!.floating)
            c.focusSettled(on: 1)
            #expect(!Self.window(c, 3)!.floating && !Self.window(c, 4)!.floating)
            // Both join the row of the window they floated over (row 0, ending at 1300), one
            // after the other at its right end, at the row's top and height.
            #expect(Self.window(c, 3)!.row == 0 && Self.window(c, 3)!.canvasFrame == Self.r(1320, 0, 320, 917))
            #expect(Self.window(c, 4)!.row == 0 && Self.window(c, 4)!.canvasFrame == Self.r(1660, 0, 320, 917))
        }
    }

    // MARK: FLOAT-04

    @Test("FLOAT-04 A floater's close gives the window you were in back its focus")
    func float04() {
        Self.withRules {
            let c = Self.rowsCanvas()
            defer { Self.finish(c) }
            let n = Fake.scWindow(id: 3, pid: Fake.firstPID, bundleID: "com.example.calc", appName: "Calc",
                                  frame: CGRect(x: 300, y: 700, width: 320, height: 480))
            Self.scan(c, [c.windows[0].scWindow, c.windows[1].scWindow, n], standard: [3])
            let w = Self.window(c, 3)!
            #expect(w.returnTo === Self.window(c, 2) || w.returnTo === Self.window(c, 1))
            // Still its app's focused window when it goes: the window you were in takes focus.
            c.focusedWindowByApp[w.pid] = w.id
            c.remove(w)
            #expect(c.lastFocusRequest?.id == c.windows.last { !$0.floating }?.id)
            // And it isn't in the layout it left behind.
            #expect(!c.windows.contains { $0.id == 3 })
        }
    }

    // MARK: FLOAT-05

    @Test("FLOAT-05 Turning Rows off frees the floaters where they are")
    func float05() {
        Self.withRules {
            let c = Self.rowsCanvas()
            defer { Self.finish(c) }
            let n = Fake.scWindow(id: 3, pid: Fake.firstPID, bundleID: "com.example.calc", appName: "Calc",
                                  frame: CGRect(x: 300, y: 700, width: 320, height: 480))
            Self.scan(c, [c.windows[0].scWindow, c.windows[1].scWindow, n], standard: [3])
            #expect(Self.window(c, 3)!.floating)
            c.rowsMode = false
            #expect(!Self.window(c, 3)!.floating && Self.window(c, 3)!.returnTo == nil)
        }
    }
}
