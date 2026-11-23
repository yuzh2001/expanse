import AppKit
import os

/// Raw touches from every trackpad, through MultitouchSupport: private, but it's how
/// BetterTouchTool and Jitouch read gestures, and it needs no permission (Accessibility, which
/// Expanse already has, would do anyway). Loaded with dlopen: without it, gestures are just off.
/// Touch frames arrive on the framework's own thread; a swipe goes to the main one, like a
/// monitor's event (see ScrollTap). Nothing is swallowed: macOS's own swipes still fire too, so
/// they want the same finger counts off in Trackpad settings.
final class TrackpadGestures {
    /// Called with each swipe: its finger count (3 or 4) and direction. On the main thread.
    var onSwipe: ((Int, CanvasController.Direction) -> Void)?
    /// Off while the setting's off: frames are ignored, a gesture under way forgotten. Set on the
    /// main thread, read on the touch thread, so a lock (see ScrollTap).
    var enabled: Bool {
        get { on.withLock { $0 } }
        set { on.withLock { $0 = newValue } }
    }
    private let on = OSAllocatedUnfairLock(initialState: true)

    private typealias Callback = @convention(c) (UnsafeMutableRawPointer?, UnsafeMutableRawPointer?, Int32, Double, Int32) -> Int32
    private typealias CreateList = @convention(c) () -> Unmanaged<CFMutableArray>?
    private typealias Register = @convention(c) (UnsafeMutableRawPointer, Callback) -> Void
    private typealias Run = @convention(c) (UnsafeMutableRawPointer, Int32) -> Void
    private typealias Halt = @convention(c) (UnsafeMutableRawPointer) -> Void

    private static let framework = dlopen("/System/Library/PrivateFrameworks/MultitouchSupport.framework/MultitouchSupport", RTLD_LAZY)
    private static func sym<T>(_ name: String, _: T.Type) -> T? {
        guard let framework, let p = dlsym(framework, name) else { return nil }
        return unsafeBitCast(p, to: T.self)
    }
    private static let createList = sym("MTDeviceCreateList", CreateList.self)
    private static let register = sym("MTRegisterContactFrameCallback", Register.self)
    private static let unregister = sym("MTUnregisterContactFrameCallback", Register.self)
    private static let run = sym("MTDeviceStart", Run.self)
    private static let halt = sym("MTDeviceStop", Halt.self)

    /// The one listening instance, for the C callback (which can't carry context).
    private static let currentLock = NSLock()
    private static var current: TrackpadGestures?

    /// One touch record (MTTouch): 96 bytes; state at 20, normalized position (x, y; 0…1, y up) at
    /// 32 and 36.
    private static let stride = 96
    private static let callback: Callback = { device, touches, count, timestamp, _ in
        currentLock.withLock { current }?.frame(device, touches, Int(count), timestamp)
        return 0
    }

    private let lock = NSLock()
    private var recognizers: [UInt: SwipeRecognizer] = [:]
    private var devices: CFArray?

    /// Listens on every trackpad there is, the built-in one and Magic Trackpads alike. False when
    /// there's none, or MultitouchSupport isn't available: swipes are just off then.
    func start() -> Bool {
        guard let createList = Self.createList, let register = Self.register, let run = Self.run,
              let list = createList()?.takeRetainedValue(), CFArrayGetCount(list) > 0 else { return false }
        Self.currentLock.withLock { Self.current = self }
        for i in 0..<CFArrayGetCount(list) {
            guard let device = UnsafeMutableRawPointer(mutating: CFArrayGetValueAtIndex(list, i)) else { continue }
            register(device, Self.callback)
            run(device, 0)
        }
        devices = list  // keeps the devices alive
        return true
    }

    func stop() {
        guard let list = devices else { return }
        for i in 0..<CFArrayGetCount(list) {
            guard let device = UnsafeMutableRawPointer(mutating: CFArrayGetValueAtIndex(list, i)) else { continue }
            Self.unregister?(device, Self.callback)
            Self.halt?(device)
        }
        devices = nil
        lock.withLock { recognizers = [:] }
        Self.currentLock.withLock { if Self.current === self { Self.current = nil } }
    }

    /// A frame of touches from one device: how many fingers are down, and their center.
    private func frame(_ device: UnsafeMutableRawPointer?, _ touches: UnsafeMutableRawPointer?, _ n: Int, _ t: Double) {
        var count = 0, x = 0.0, y = 0.0
        if let touches {
            for i in 0..<n {
                let f = touches + i * Self.stride
                let state = f.load(fromByteOffset: 20, as: Int32.self)
                guard state == 3 || state == 4 else { continue }  // making contact, or touching
                let px = Double(f.load(fromByteOffset: 32, as: Float.self)),
                    py = Double(f.load(fromByteOffset: 36, as: Float.self))
                guard (-0.1...1.1).contains(px), (-0.1...1.1).contains(py) else { continue }  // not a touch we understand
                count += 1
                x += px
                y += py
            }
        }
        if count > 0 { x /= Double(count); y /= Double(count) }
        // Off: forget any gesture under way, so re-enabling with fingers down can't fire it.
        guard enabled else { lock.withLock { recognizers = [:] }; return }
        let key = UInt(bitPattern: device)
        let events = lock.withLock { () -> [SwipeRecognizer.Event] in
            var r = recognizers[key] ?? SwipeRecognizer()
            let e = r.frame(count: count, x: x, y: y)
            recognizers[key] = r
            return e
        }
        for event in events {
            guard case .swipe(let fingers, let direction) = event else { continue }
            DispatchQueue.main.async { [weak self] in self?.onSwipe?(fingers, direction) }
        }
    }
}

/// Turns raw trackpad frames (how many fingers touch, and where their center is) into swipes.
///
/// A swipe starts when three or four fingers touch — the count latches, and fingers that land a
/// frame apart still make one gesture. Once their center travels far enough one way it fires
/// once, then nothing until every finger lifts. Any other count (typing palms, two-finger
/// scrolls, Three-Finger Drag) is ignored.
struct SwipeRecognizer {
    enum Event: Equatable {
        /// The swipe's finger count and direction.
        case swipe(fingers: Int, direction: CanvasController.Direction)
    }

    private enum Phase { case idle, undecided, done }
    private var phase = Phase.idle
    /// How many fingers this swipe has, 3 or 4.
    private var fingers = 0
    private var origin = (x: 0.0, y: 0.0)
    /// Frames the finger count has held still for. A swipe can't fire until it settles: real
    /// fingers land a frame or two apart, and a fourth joining late mustn't leave the swipe
    /// latched as a three-finger one (it would hop instead of toggling the canvas).
    private var settled = 0

    /// How far the center must move before it's a swipe (a fraction of the trackpad's width), and
    /// how much the longer axis must beat the shorter by for the direction to count.
    static let travel = 0.05, dominance = 1.2
    /// Frames the finger count must hold still before a swipe may fire: about 30ms at the
    /// trackpad's ~100Hz, imperceptible but long enough for a late finger to join.
    static let settle = 3

    /// One trackpad frame: `count` fingers touching, their center at (`x`, `y`) in 0…1 (y up).
    mutating func frame(count: Int, x: Double, y: Double) -> [Event] {
        switch phase {
        case .idle:
            guard count == 3 || count == 4 else { return [] }
            fingers = count
            origin = (x, y)
            settled = 0
            phase = .undecided
            return []
        case .undecided:
            if count == 0 { phase = .idle; return [] }
            if count == 3 || count == 4 {
                // A finger joining or leaving before the swipe starts: the gesture's count
                // relatches, the settle window restarts, and travel is measured from here.
                if count != fingers { fingers = count; origin = (x, y); settled = 0 }
                else { settled += 1 }
            } else {
                phase = .done
                return []
            }
            guard settled >= Self.settle else { return [] }
            let (dx, dy) = (x - origin.x, y - origin.y)
            guard abs(dx) > Self.travel || abs(dy) > Self.travel,
                  max(abs(dx), abs(dy)) > Self.dominance * min(abs(dx), abs(dy)) else { return [] }
            phase = .done
            return [.swipe(fingers: fingers, direction: abs(dx) > abs(dy) ? (dx > 0 ? .right : .left) : (dy > 0 ? .up : .down))]
        case .done:
            if count == 0 { phase = .idle }
            return []
        }
    }
}
