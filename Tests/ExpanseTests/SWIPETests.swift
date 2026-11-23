import Testing
import AppKit
@_private(sourceFile: "TrackpadGestures.swift") @testable import Expanse
@_private(sourceFile: "CanvasController.swift") @testable import Expanse

/// TrackpadGestures.SwipeRecognizer: raw finger counts and centers in, swipes out. The frames are
/// fractions of the trackpad (0…1, y up), a swipe firing once per touch-down.
@Suite("SWIPE: Trackpad swipe recognition") struct SWIPETests {

    /// `steps` of (fingers down, center x, center y), events collected.
    private static func run(_ steps: [(Int, Double, Double)]) -> [SwipeRecognizer.Event] {
        var r = SwipeRecognizer()
        return steps.flatMap { r.frame(count: $0, x: $1, y: $2) }
    }

    private static func swipe(_ fingers: Int, _ d: CanvasController.Direction) -> SwipeRecognizer.Event {
        .swipe(fingers: fingers, direction: d)
    }

    @Test("A four-finger swipe up fires once")
    func fourUp() {
        let events = Self.run([(4, 0.5, 0.5), (4, 0.5, 0.53), (4, 0.5, 0.57), (4, 0.5, 0.7), (0, 0, 0)])
        #expect(events == [Self.swipe(4, .up)])
    }

    @Test("A three-finger swipe fires in each direction")
    func threeAllWays() {
        #expect(Self.run([(3, 0.5, 0.5), (3, 0.5, 0.58)]) == [Self.swipe(3, .up)])
        #expect(Self.run([(3, 0.5, 0.5), (3, 0.5, 0.42)]) == [Self.swipe(3, .down)])
        #expect(Self.run([(3, 0.5, 0.5), (3, 0.58, 0.5)]) == [Self.swipe(3, .right)])
        #expect(Self.run([(3, 0.5, 0.5), (3, 0.42, 0.5)]) == [Self.swipe(3, .left)])
    }

    @Test("Fingers landing a frame apart make one swipe of the final count")
    func staggered() {
        // Three fingers down, then a fourth joins before the center moves: a four-finger swipe.
        #expect(Self.run([(3, 0.5, 0.5), (4, 0.51, 0.51), (4, 0.51, 0.58)]) == [Self.swipe(4, .up)])
    }

    @Test("Two-finger scrolls and palms never fire")
    func otherCounts() {
        #expect(Self.run([(2, 0.5, 0.5), (2, 0.5, 0.8), (2, 0.8, 0.8), (0, 0, 0)]).isEmpty)
        #expect(Self.run([(5, 0.5, 0.5), (5, 0.5, 0.8), (0, 0, 0)]).isEmpty)
    }

    @Test("A drift below the threshold, or a diagonal that isn't dominant, doesn't fire")
    func undecided() {
        #expect(Self.run([(3, 0.5, 0.5), (3, 0.52, 0.51), (3, 0.54, 0.52), (0, 0, 0)]).isEmpty)
        #expect(Self.run([(3, 0.5, 0.5), (3, 0.56, 0.56), (0, 0, 0)]).isEmpty)
    }

    @Test("A finger lifting before the swipe aborts it")
    func abortEarly() {
        #expect(Self.run([(3, 0.5, 0.5), (3, 0.5, 0.52), (2, 0.5, 0.52), (3, 0.5, 0.6), (0, 0, 0)]).isEmpty)
    }

    @Test("After firing, the rest of the touch-down is quiet, then the next fires")
    func rearm() {
        let events = Self.run([(4, 0.5, 0.5), (4, 0.5, 0.58), (4, 0.5, 0.9), (0, 0, 0),
                               (4, 0.5, 0.5), (4, 0.42, 0.5), (0, 0, 0)])
        #expect(events == [Self.swipe(4, .up), Self.swipe(4, .left)])
    }
}
