import Testing
import AppKit
@_private(sourceFile: "TrackpadGestures.swift") @testable import Expanse
@_private(sourceFile: "CanvasController.swift") @testable import Expanse
@_private(sourceFile: "MenuPanel.swift") @testable import Expanse

/// TrackpadGestures.SwipeRecognizer: raw finger counts and centers in, gestures out. The frames
/// are fractions of the trackpad (0…1, y up): three settled fingers report every move as a pan,
/// four fire one swipe per touch-down — and only once the finger count has held still for a few
/// frames, so a finger landing late still joins it.
@Suite("SWIPE: Trackpad swipe recognition") struct SWIPETests {

    /// `steps` of (fingers down, center x, center y), events collected.
    private static func run(_ steps: [(Int, Double, Double)]) -> [SwipeRecognizer.Event] {
        var r = SwipeRecognizer()
        return steps.flatMap { r.frame(count: $0, x: $1, y: $2) }
    }

    private static func swipe(_ fingers: Int, _ d: CanvasController.Direction) -> SwipeRecognizer.Event {
        .swipe(fingers: fingers, direction: d)
    }

    /// The pan deltas in `events` — Doubles that can't be compared exactly.
    private static func pans(_ events: [SwipeRecognizer.Event]) -> [(dx: Double, dy: Double)] {
        events.compactMap { if case .pan(let dx, let dy) = $0 { return (dx, dy) }; return nil }
    }

    @Test("SWIPE-01 A four-finger swipe fires once, up or down")
    func fourUpDown() {
        let up = Self.run([(4, 0.5, 0.5), (4, 0.5, 0.53), (4, 0.5, 0.57), (4, 0.5, 0.7), (0, 0, 0)])
        #expect(up == [Self.swipe(4, .up)])
        let down = Self.run([(4, 0.5, 0.5), (4, 0.5, 0.47), (4, 0.5, 0.43), (4, 0.5, 0.3), (0, 0, 0)])
        #expect(down == [Self.swipe(4, .down)])
    }

    @Test("SWIPE-01 Three settled fingers pan with every move, ending when they lift")
    func threePans() {
        let events = Self.run([(3, 0.5, 0.5), (3, 0.5, 0.52), (3, 0.5, 0.55), (3, 0.5, 0.58),
                               (3, 0.5, 0.62), (0, 0, 0)])
        let pans = Self.pans(events)
        // Two settled moving frames: two deltas, and the pan ends on lift.
        #expect(pans.count == 2 && pans.allSatisfy { $0.dx == 0 && $0.dy > 0 })
        #expect(events.last == .panEnd)
        // Diagonals report both axes.
        #expect(Self.pans(Self.run([(3, 0.5, 0.5), (3, 0.52, 0.52), (3, 0.55, 0.55), (3, 0.58, 0.58)]))
                .allSatisfy { $0.dx > 0 && $0.dy > 0 })
    }

    @Test("SWIPE-01 A finger joining or leaving ends the pan")
    func panEnds() {
        // Three panning, one lifts: the pan ends and nothing more comes of the touch.
        #expect(Self.run([(3, 0.5, 0.5), (3, 0.5, 0.52), (3, 0.5, 0.55), (3, 0.5, 0.58),
                          (2, 0.5, 0.58), (2, 0.5, 0.8)]).last == .panEnd)
        // A fourth joining: the pan ends, the touch is a four-finger candidate again.
        let events = Self.run([(3, 0.5, 0.5), (3, 0.5, 0.53), (3, 0.5, 0.56), (3, 0.5, 0.59),
                               (4, 0.5, 0.5), (4, 0.5, 0.52), (4, 0.5, 0.55), (4, 0.5, 0.58), (4, 0.5, 0.62)])
        #expect(events.contains(.panEnd) && events.last == Self.swipe(4, .up))
    }

    @Test("SWIPE-01 Fingers landing a frame apart make one swipe of the final count")
    func staggered() {
        // Three fingers down, then a fourth joins before the gesture settles: a four-finger swipe.
        #expect(Self.run([(3, 0.5, 0.5), (4, 0.51, 0.51), (4, 0.51, 0.53), (4, 0.51, 0.56), (4, 0.51, 0.6)])
                == [Self.swipe(4, .up)])
    }

    @Test("SWIPE-02 Two-finger scrolls and palms never fire")
    func otherCounts() {
        #expect(Self.run([(2, 0.5, 0.5), (2, 0.5, 0.8), (2, 0.8, 0.8), (0, 0, 0)]).isEmpty)
        #expect(Self.run([(5, 0.5, 0.5), (5, 0.5, 0.8), (0, 0, 0)]).isEmpty)
    }

    @Test("SWIPE-02 Four fingers drifting below the threshold, or diagonally, don't fire")
    func undecided() {
        #expect(Self.run([(4, 0.5, 0.5), (4, 0.51, 0.5), (4, 0.52, 0.5), (4, 0.53, 0.5), (0, 0, 0)]).isEmpty)
        #expect(Self.run([(4, 0.5, 0.5), (4, 0.53, 0.53), (4, 0.55, 0.55), (4, 0.56, 0.56), (0, 0, 0)]).isEmpty)
    }

    @Test("SWIPE-02 A finger lifting before the swipe aborts it")
    func abortEarly() {
        #expect(Self.run([(4, 0.5, 0.5), (4, 0.5, 0.52), (2, 0.5, 0.52), (3, 0.5, 0.6), (0, 0, 0)]).isEmpty)
    }

    @Test("SWIPE-01 After firing, the rest of the touch-down is quiet, then the next fires")
    func rearm() {
        let events = Self.run([(4, 0.5, 0.5), (4, 0.5, 0.55), (4, 0.5, 0.6), (4, 0.5, 0.9), (0, 0, 0),
                               (4, 0.5, 0.5), (4, 0.48, 0.5), (4, 0.45, 0.5), (4, 0.42, 0.5), (0, 0, 0)])
        #expect(events == [Self.swipe(4, .up), Self.swipe(4, .left)])
    }

    @Test("SWIPE-01 Fingers left on the pad after a swipe don't pan")
    func noPanAfterSwipe() {
        // The swipe fired: dropping to three fingers mid-arc doesn't restart as a pan.
        #expect(Self.run([(4, 0.5, 0.5), (4, 0.5, 0.55), (4, 0.5, 0.6), (4, 0.5, 0.9),
                          (3, 0.5, 0.9), (3, 0.5, 0.8), (0, 0, 0)]) == [Self.swipe(4, .up)])
    }

    @Test("SWIPE-03 Off, every frame is dropped and a gesture under way forgotten")
    func offGate() {
        // The panel's switch leaves the panel open and needs no canvas.
        #expect(!MenuPanel.Action.gestures(false).closesPanel)
        #expect(!MenuPanel.Action.gestures(false).needsCanvas)
        let g = TrackpadGestures()
        let device = UnsafeMutableRawPointer.allocate(byteCount: 8, alignment: 8)
        defer { device.deallocate() }
        let touches = UnsafeMutableRawPointer.allocate(byteCount: 4 * TrackpadGestures.stride, alignment: 8)
        defer { touches.deallocate() }
        for i in 0..<4 {
            let f = touches + i * TrackpadGestures.stride
            f.storeBytes(of: Int32(4), toByteOffset: 20, as: Int32.self)
            f.storeBytes(of: Float(0.5), toByteOffset: 32, as: Float.self)
            f.storeBytes(of: Float(0.5), toByteOffset: 36, as: Float.self)
        }
        // Three fingers down: a gesture begins, its recognizer kept for the device.
        g.frame(device, touches, 3, 0)
        #expect(g.recognizers.count == 1)
        // Off: frames are dropped whole and the gesture under way forgotten, so fingers still
        // down when it comes back on can't finish it.
        g.enabled = false
        g.frame(device, touches, 3, 0.1)
        #expect(g.recognizers.isEmpty)
        g.frame(device, touches, 3, 0.2)
        #expect(g.recognizers.isEmpty)
    }

    @Test("SWIPE-04 A swipe's fingers still down suppress its scrolls until they lift")
    func suppressScrolls() {
        let g = TrackpadGestures()
        let device = UnsafeMutableRawPointer.allocate(byteCount: 8, alignment: 8)
        defer { device.deallocate() }
        let touches = UnsafeMutableRawPointer.allocate(byteCount: 4 * TrackpadGestures.stride, alignment: 8)
        defer { touches.deallocate() }
        func touch(_ n: Int, y: Float, at t: Double) {
            for i in 0..<n {
                let f = touches + i * TrackpadGestures.stride
                f.storeBytes(of: Int32(4), toByteOffset: 20, as: Int32.self)
                f.storeBytes(of: Float(0.5), toByteOffset: 32, as: Float.self)
                f.storeBytes(of: y, toByteOffset: 36, as: Float.self)
            }
            g.frame(device, touches, n, t)
        }
        // A four-finger swipe up, fingers still down after it fires: their moves aren't scrolls.
        touch(4, y: 0.5, at: 0); touch(4, y: 0.55, at: 0.01); touch(4, y: 0.6, at: 0.02)
        touch(4, y: 0.7, at: 0.03); touch(4, y: 0.8, at: 0.04)
        #expect(g.suppressesScrolls)
        // Two fingers lift and the rest keep moving — still the swipe's touch, still no scroll.
        touch(2, y: 0.85, at: 0.05); touch(2, y: 0.9, at: 0.06)
        #expect(g.suppressesScrolls)
        // All fingers lift: the next touch, two fingers, is a scroll again — though the swipe's
        // having just fired still counts for the gap to its delivery (see firedWithin).
        touch(0, y: 0, at: 0.07)
        #expect(!g.suppressesScrolls)
        #expect(g.firedWithin(0.3) && !g.firedWithin(0))
        touch(2, y: 0.5, at: 0.08); touch(2, y: 0.6, at: 0.09)
        #expect(!g.suppressesScrolls)
        // Off: nothing is suppressed.
        g.enabled = false
        touch(4, y: 0.5, at: 0.10)
        #expect(!g.suppressesScrolls)
    }
}
