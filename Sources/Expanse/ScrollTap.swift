import AppKit
import os

/// ⌃⌥ + scroll moves the canvas from anywhere, over windows too (NAV-66), and the app under the
/// pointer gets none of the gesture. A global NSEvent monitor only watches: the first ticks of a
/// gesture still reach that app. An active event tap can drop events, and this one drops a taken
/// gesture whole. It takes Accessibility, which Expanse already needs.
///
/// Every scroll in the session runs its callback, so it runs on a thread of its own, never the
/// main one: a busy main thread (or a beachballing app Expanse is waiting on through
/// Accessibility) must not stall scrolling for everything. What it takes goes to the main
/// thread as an NSEvent, like a monitor would give it.
final class ScrollTap {
    /// Called with each scroll event the tap takes, on the main thread.
    var handler: ((NSEvent) -> Void)?

    /// Off while Expanse is paused: everything passes, and a gesture under way is let go.
    /// Set on the main thread, read on the tap's, so a lock.
    var enabled: Bool {
        get { on.withLock { $0 } }
        set { on.withLock { $0 = newValue } }
    }

    private let on = OSAllocatedUnfairLock(initialState: true)
    /// A gesture the tap took stays taken to its end — the momentum after too — ⌃⌥ held or not.
    /// Only the tap's thread reads and writes it.
    private var taking = false
    private var tap: CFMachPort?

    /// Makes the tap and starts the thread it runs on. False when it can't be made — no
    /// Accessibility yet: the monitors' ⌃⌥ branch is the fallback then (see CanvasController).
    func start() -> Bool {
        guard tap == nil else { return true }
        guard let port = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap,
                                           options: .defaultTap,
                                           eventsOfInterest: CGEventMask(1 << CGEventType.scrollWheel.rawValue),
                                           callback: Self.callback,
                                           userInfo: Unmanaged.passUnretained(self).toOpaque()),
              let source = CFMachPortCreateRunLoopSource(nil, port, 0) else { return false }
        tap = port
        let thread = Thread {
            let loop = CFRunLoopGetCurrent()!
            CFRunLoopAddSource(loop, source, .commonModes)
            CGEvent.tapEnable(tap: port, enable: true)
            CFRunLoopRun()
        }
        thread.name = "com.invignation.expanse.scrolltap"
        thread.start()
        return true
    }

    /// A gesture's first event: began or mayBegin, or a mouse wheel's tick (no phase at all, so
    /// each counts on its own). At the first, ⌃⌥ down — and not ⌘, scrollTakesOverAnywhere's
    /// rule, in CGEventFlags — takes the gesture. After that it stays taken whatever the flags,
    /// so letting ⌃⌥ go mid-gesture keeps its tail, and the momentum after it, from the app.
    static func takes(scrollPhase: Int64, momentumPhase: Int64, flags: CGEventFlags, taking: Bool) -> Bool {
        // CGScrollPhase's values, not NSEvent.Phase's: began 1, changed 2, ended 4, cancelled 8,
        // mayBegin 128. Momentum's is its own field: began 1, continue 2, end 3.
        let start = scrollPhase == 1 || scrollPhase == 128 || (scrollPhase == 0 && momentumPhase == 0)
        guard start else { return taking }
        return flags.contains([.maskControl, .maskAlternate]) && !flags.contains(.maskCommand)
    }

    /// The tap's C callback. `self` rides along in userInfo, unretained: the tap lives as long
    /// as the app, so it can't outlive it.
    private static let callback: CGEventTapCallBack = { _, type, event, userInfo in
        guard let userInfo else { return Unmanaged.passUnretained(event) }
        let me = Unmanaged<ScrollTap>.fromOpaque(userInfo).takeUnretainedValue()
        switch type {
        case .tapDisabledByTimeout, .tapDisabledByUserInput:
            // macOS turns the tap off when the callback falls behind: back on, and the event
            // goes through rather than getting lost.
            if let tap = me.tap { CGEvent.tapEnable(tap: tap, enable: true) }
            return Unmanaged.passUnretained(event)
        case .scrollWheel:
            break
        default:
            return Unmanaged.passUnretained(event)
        }
        guard me.enabled else {
            me.taking = false
            return Unmanaged.passUnretained(event)
        }
        let take = takes(scrollPhase: event.getIntegerValueField(.scrollWheelEventScrollPhase),
                         momentumPhase: event.getIntegerValueField(.scrollWheelEventMomentumPhase),
                         flags: event.flags, taking: me.taking)
        me.taking = take
        guard take, let nsEvent = NSEvent(cgEvent: event) else { return Unmanaged.passUnretained(event) }
        DispatchQueue.main.async { me.handler?(nsEvent) }
        // nil: swallowed, so it never reaches the app under the pointer.
        return nil
    }
}
