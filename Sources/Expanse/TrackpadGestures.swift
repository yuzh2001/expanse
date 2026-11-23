import AppKit
import os

/// Raw touches from every trackpad, through MultitouchSupport: private, but it's how
/// BetterTouchTool and Jitouch read gestures, and it needs no permission (Accessibility, which
/// Expanse already has, would do anyway). Loaded with dlopen: without it, gestures are just off.
/// Touch frames arrive on the framework's own thread; a swipe goes to the main one, like a
/// monitor's event (see ScrollTap). Nothing is swallowed: macOS's own swipes still fire too, so
/// they want the same finger counts off in Trackpad settings.
final class TrackpadGestures {
    /// Called with each four-finger swipe: its direction (up toggles the canvas, down dives
    /// into the window under the mouse). On the main thread.
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
    private typealias SurfaceSize = @convention(c) (UnsafeMutableRawPointer, UnsafeMutablePointer<Int32>, UnsafeMutablePointer<Int32>) -> Int32

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
    private static let surfaceSize = sym("MTDeviceGetSensorSurfaceDimensions", SurfaceSize.self)

    /// The one listening instance, for the C callback (which can't carry context).
    private static let currentLock = NSLock()
    private static var current: TrackpadGestures?

    /// One touch record (MTTouch): 96 bytes, the layout OpenMultitouchSupport and Trident
    /// verified on-device — pathIndex at 16, state at 20 (3–5 all mean on the surface),
    /// normalized position (x, y; 0…1, y up) at 32 and 36, contact size `zTotal` at 48,
    /// angle at 56, ellipse axes at 60 and 64, zDensity at 92.
    private static let stride = 96
    private static let callback: Callback = { device, touches, count, timestamp, _ in
        currentLock.withLock { current }?.frame(device, touches, Int(count), timestamp)
        return 0
    }

    /// `defaults write com.invignation.expanse.dev touchDump -bool YES`: log each touch's size and
    /// axes, for picking a palm filter from real hardware (remove once tuned).
    private let touchDump = UserDefaults.standard.bool(forKey: "touchDump")
    private var lastDump = Date.distantPast

    private let lock = NSLock()
    private var recognizers: [UInt: SwipeRecognizer] = [:]
    private var palmFilters: [UInt: PalmFilter] = [:]
    /// When the last swipe fired (same lock): the gap between a recognizer going idle and the
    /// swipe's async delivery can't let a scroll through either.
    private var lastFire = Date.distantPast
    private var devices: CFArray?

    /// A trackpad's touch sequence is a swipe's and gestures are on: three or more fingers down
    /// (the swipe still being made up), or one already decided whose fingers haven't all lifted
    /// — some may have left, and the rest still aren't scrolling. While it holds, the fingers'
    /// moves aren't scrolls: they would pan or zoom the canvas the swipe just opened, and at
    /// 100% a desktop scroll would open it before the swipe could.
    var suppressesScrolls: Bool {
        enabled && lock.withLock { recognizers.values.contains { $0.down >= 3 || $0.done } }
    }

    /// A swipe fired less than `s` seconds ago, and gestures are on: covers the gap between the
    /// recognizer going idle and the swipe's async delivery, when a flick's lift tick lands.
    func firedWithin(_ s: TimeInterval) -> Bool {
        enabled && lock.withLock { Date().timeIntervalSince(lastFire) < s }
    }

    /// Listens on every trackpad there is, the built-in one and Magic Trackpads alike. False when
    /// there's none, or MultitouchSupport isn't available: swipes are just off then.
    func start() -> Bool {
        guard let createList = Self.createList, let register = Self.register, let run = Self.run,
              let list = createList()?.takeRetainedValue(), CFArrayGetCount(list) > 0 else { return false }
        Self.currentLock.withLock { Self.current = self }
        for i in 0..<CFArrayGetCount(list) {
            guard let device = UnsafeMutableRawPointer(mutating: CFArrayGetValueAtIndex(list, i)) else { continue }
            var w: Int32 = 0, h: Int32 = 0
            if let surfaceSize = Self.surfaceSize, surfaceSize(device, &w, &h) == 0, w > 0, h > 0 {
                lock.withLock { palmFilters[UInt(bitPattern: device)] = PalmFilter(surfaceMM: (Float(w) / 100, Float(h) / 100)) }
            }
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
        lock.withLock { recognizers = [:]; palmFilters = [:] }
        Self.currentLock.withLock { if Self.current === self { Self.current = nil } }
    }

    /// A frame of touches from one device: how many fingers are down, and their center —
    /// palms already filtered out, so a palm heel plus two fingers is still two.
    private func frame(_ device: UnsafeMutableRawPointer?, _ touches: UnsafeMutableRawPointer?, _ n: Int, _ t: Double) {
        var contacts: [(path: Int32, x: Float, y: Float, size: Float)] = []
        if let touches {
            var dump = touchDump && Date().timeIntervalSince(lastDump) > 0.5 ? "" : nil
            for i in 0..<n {
                let f = touches + i * Self.stride
                let state = f.load(fromByteOffset: 20, as: Int32.self)
                guard (3...5).contains(state) else { continue }  // on-surface: make / touching / break
                let px = Double(f.load(fromByteOffset: 32, as: Float.self)),
                    py = Double(f.load(fromByteOffset: 36, as: Float.self))
                guard (-0.1...1.1).contains(px), (-0.1...1.1).contains(py) else { continue }  // not a touch we understand
                let path = f.load(fromByteOffset: 16, as: Int32.self),
                    zTotal = f.load(fromByteOffset: 48, as: Float.self)
                if dump != nil {
                    dump! += " \(i):path=\(path) st=\(state) s=\(zTotal) x=\(px) y=\(py)"
                }
                contacts.append((path, Float(px), Float(py), zTotal))
            }
            if let dump, !dump.isEmpty {
                lastDump = Date()
                logger.info("touch\(dump, privacy: .public)")
            }
        }
        let key = UInt(bitPattern: device)
        let pts = lock.withLock { () -> [(x: Float, y: Float)] in
            var f = palmFilters[key] ?? PalmFilter()
            let r = f.fingers(contacts)
            palmFilters[key] = f
            return r
        }
        var count = pts.count, x = 0.0, y = 0.0
        for p in pts { x += Double(p.x); y += Double(p.y) }
        if count > 0 { x /= Double(count); y /= Double(count) }
        // Off: forget any gesture under way, so re-enabling with fingers down can't fire it.
        guard enabled else { lock.withLock { recognizers = [:]; palmFilters = [:] }; return }
        let events = lock.withLock { () -> [SwipeRecognizer.Event] in
            var r = recognizers[key] ?? SwipeRecognizer()
            let e = r.frame(count: count, x: x, y: y)
            recognizers[key] = r
            return e
        }
        for event in events {
            switch event {
            case .swipe(let fingers, let direction):
                lock.withLock { lastFire = Date() }
                DispatchQueue.main.async { [weak self] in self?.onSwipe?(fingers, direction) }
            }
        }
    }
}

/// Turns raw trackpad frames (how many fingers touch, and where their center is) into one
/// gesture: a settled four-finger move fires a swipe, once per touch-down.
///
/// A gesture starts only at four fingers — three fingers land first on most real swipes,
/// so the count must hold still for a few frames before the center's travel can fire it,
/// and a finger landing or leaving late means it was never a four-finger swipe at all.
/// Any other count (typing palms, two-finger scrolls, Three-Finger Drag) is ignored.
struct SwipeRecognizer {
    enum Event: Equatable {
        /// A four-finger swipe's direction (up toggles the canvas, down dives into a window).
        case swipe(fingers: Int, direction: CanvasController.Direction)
    }

    private enum Phase { case idle, undecided, done }
    private var phase = Phase.idle
    private var origin = (x: 0.0, y: 0.0)
    /// Fingers touching in the last frame (any count), so a gesture's owner can ignore the
    /// scroll events the same fingers keep making (see TrackpadGestures.suppressesScrolls).
    private(set) var down = 0
    /// A gesture has been decided (fired, or aborted by a finger leaving) and not all fingers
    /// have lifted: what they still do isn't a scroll either.
    var done: Bool { phase == .done }
    /// Frames the finger count has held still for. A swipe can't fire until it settles: real
    /// fingers land a frame or two apart, and a late joiner mustn't fire a gesture the first
    /// three were already making.
    private var settled = 0

    /// How far the center must move before four fingers make a swipe (a fraction of the
    /// trackpad's width), and how much the longer axis must beat the shorter by for the
    /// direction to count.
    static let travel = 0.05, dominance = 1.2
    /// Frames the finger count must hold still before a gesture may start: about 30ms at the
    /// trackpad's ~100Hz, imperceptible but long enough for a late finger to join.
    static let settle = 3

    /// One trackpad frame: `count` fingers touching, their center at (`x`, `y`) in 0…1 (y up).
    mutating func frame(count: Int, x: Double, y: Double) -> [Event] {
        down = count
        switch phase {
        case .idle:
            guard count == 4 else { return [] }
            origin = (x, y)
            settled = 0
            phase = .undecided
            return []
        case .undecided:
            if count == 0 {
                phase = .idle
                return []
            }
            guard count == 4 else {
                // A finger joining or leaving early: it wasn't a four-finger swipe, and it
                // can't become one until all fingers lift.
                phase = .done
                return []
            }
            settled += 1
            guard settled >= Self.settle else { return [] }
            let (dx, dy) = (x - origin.x, y - origin.y)
            guard abs(dx) > Self.travel || abs(dy) > Self.travel,
                  max(abs(dx), abs(dy)) > Self.dominance * min(abs(dx), abs(dy)) else { return [] }
            phase = .done
            return [.swipe(fingers: 4, direction: abs(dx) > abs(dy) ? (dx > 0 ? .right : .left) : (dy > 0 ? .up : .down))]
        case .done:
            if count == 0 { phase = .idle }
            return []
        }
    }
}

/// Palm rejection on raw contacts, the strategy Trident validated on-device: a contact whose
/// size passes the cap is a palm wherever it sits, and one *born* inside a band in from the
/// left, right, or near edge stays a palm for its whole life — palm heels and resting thumbs
/// land there, while a finger that drifts to the rim mid-gesture was born elsewhere and still
/// counts. Contacts are keyed on their persistent pathIndex, so a rejected palm can't move
/// into validity; paths that leave the surface are forgotten, so the sensor can reuse indices.
/// (macOS's own palm suppression happens in the recognizer layer above this raw stream, which
/// is why it has to be done here at all.)
struct PalmFilter {
    /// Contact-size cap: bigger than this and it's a palm (Trident's tested band is 1.2–2.0;
    /// 1.6 sits in the middle). In zTotal units, not millimetres.
    static let maxSize: Float = 1.6
    /// The rim band in mm where a born contact is presumed a palm (Trident's default).
    static let bandMM: Float = 7
    /// The trackpad's surface in mm (160×115 covers built-in pads the framework reports
    /// nothing for).
    var surfaceMM = (width: Float(160), height: Float(115))
    /// Whether each live path was born inside the rim band.
    private var bornInBand: [Int32: Bool] = [:]

    /// Of `contacts` (on-surface; x, y in 0…1, y up; size = zTotal), the ones that look like
    /// fingers — positions only, for center-of-fingers math.
    mutating func fingers(_ contacts: [(path: Int32, x: Float, y: Float, size: Float)]) -> [(x: Float, y: Float)] {
        let alive = Set(contacts.map(\.path))
        bornInBand = bornInBand.filter { alive.contains($0.key) }
        let bandX = Self.bandMM / surfaceMM.width, bandY = Self.bandMM / surfaceMM.height
        return contacts.compactMap { c in
            guard c.size <= Self.maxSize else { return nil }
            if bornInBand[c.path] == nil {
                bornInBand[c.path] = c.x < bandX || c.x > 1 - bandX || c.y < bandY
            }
            return bornInBand[c.path] == true ? nil : (c.x, c.y)
        }
    }
}
