import Testing
import AppKit
@_private(sourceFile: "TrackpadGestures.swift") @testable import Expanse
@_private(sourceFile: "CanvasController.swift") @testable import Expanse
@_private(sourceFile: "MenuPanel.swift") @testable import Expanse

/// TrackpadGestures.SwipeRecognizer: raw finger counts and centers in, swipes out. The frames are
/// fractions of the trackpad (0…1, y up), a swipe firing once per touch-down — and only once the
/// finger count has held still for a few frames, so a finger landing late still joins it.
@Suite("SWIPE: Trackpad swipe recognition") struct SWIPETests {

    /// `steps` of (fingers down, center x, center y), events collected.
    private static func run(_ steps: [(Int, Double, Double)]) -> [SwipeRecognizer.Event] {
        var r = SwipeRecognizer()
        return steps.flatMap { r.frame(count: $0, x: $1, y: $2) }
    }

    private static func swipe(_ fingers: Int, _ d: CanvasController.Direction) -> SwipeRecognizer.Event {
        .swipe(fingers: fingers, direction: d)
    }

    @Test("SWIPE-01 A four-finger swipe up fires once")
    func fourUp() {
        let events = Self.run([(4, 0.5, 0.5), (4, 0.5, 0.53), (4, 0.5, 0.57), (4, 0.5, 0.7), (0, 0, 0)])
        #expect(events == [Self.swipe(4, .up)])
    }

    @Test("SWIPE-01 A three-finger swipe fires in each direction")
    func threeAllWays() {
        #expect(Self.run([(3, 0.5, 0.5), (3, 0.5, 0.52), (3, 0.5, 0.55), (3, 0.5, 0.58)]) == [Self.swipe(3, .up)])
        #expect(Self.run([(3, 0.5, 0.5), (3, 0.5, 0.48), (3, 0.5, 0.45), (3, 0.5, 0.42)]) == [Self.swipe(3, .down)])
        #expect(Self.run([(3, 0.5, 0.5), (3, 0.52, 0.5), (3, 0.55, 0.5), (3, 0.58, 0.5)]) == [Self.swipe(3, .right)])
        #expect(Self.run([(3, 0.5, 0.5), (3, 0.48, 0.5), (3, 0.45, 0.5), (3, 0.42, 0.5)]) == [Self.swipe(3, .left)])
    }

    @Test("SWIPE-01 Fingers landing a frame apart make one swipe of the final count")
    func staggered() {
        // Three fingers down, then a fourth joins before the swipe starts: a four-finger swipe.
        #expect(Self.run([(3, 0.5, 0.5), (4, 0.51, 0.51), (4, 0.51, 0.53), (4, 0.51, 0.56), (4, 0.51, 0.6)])
                == [Self.swipe(4, .up)])
    }

    @Test("SWIPE-01 Three fingers moving don't pre-empt the fourth still landing")
    func lateFourth() {
        // Three fingers already travelling — past the travel threshold but the count unsettled —
        // then the fourth joins: the swipe fires as four-fingered, not three.
        #expect(Self.run([(3, 0.5, 0.5), (3, 0.55, 0.5), (4, 0.5, 0.5), (4, 0.5, 0.53), (4, 0.5, 0.56), (4, 0.5, 0.6)])
                == [Self.swipe(4, .up)])
    }

    @Test("SWIPE-02 Two-finger scrolls and palms never fire")
    func otherCounts() {
        #expect(Self.run([(2, 0.5, 0.5), (2, 0.5, 0.8), (2, 0.8, 0.8), (0, 0, 0)]).isEmpty)
        #expect(Self.run([(5, 0.5, 0.5), (5, 0.5, 0.8), (0, 0, 0)]).isEmpty)
    }

    @Test("SWIPE-02 A drift below the threshold, or a diagonal that isn't dominant, doesn't fire")
    func undecided() {
        #expect(Self.run([(3, 0.5, 0.5), (3, 0.51, 0.5), (3, 0.52, 0.5), (3, 0.53, 0.5), (0, 0, 0)]).isEmpty)
        #expect(Self.run([(3, 0.5, 0.5), (3, 0.53, 0.53), (3, 0.55, 0.55), (3, 0.56, 0.56), (0, 0, 0)]).isEmpty)
    }

    @Test("SWIPE-02 A finger lifting before the swipe aborts it")
    func abortEarly() {
        #expect(Self.run([(3, 0.5, 0.5), (3, 0.5, 0.52), (2, 0.5, 0.52), (3, 0.5, 0.6), (0, 0, 0)]).isEmpty)
    }

    @Test("SWIPE-01 After firing, the rest of the touch-down is quiet, then the next fires")
    func rearm() {
        let events = Self.run([(4, 0.5, 0.5), (4, 0.5, 0.55), (4, 0.5, 0.6), (4, 0.5, 0.9), (0, 0, 0),
                               (4, 0.5, 0.5), (4, 0.48, 0.5), (4, 0.45, 0.5), (4, 0.42, 0.5), (0, 0, 0)])
        #expect(events == [Self.swipe(4, .up), Self.swipe(4, .left)])
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
}
