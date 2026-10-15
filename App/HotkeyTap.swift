import Carbon
import CoreGraphics
import Foundation
import KotobaCore
import Synchronization

/// Reports the Ctrl+Opt+Cmd chord and Esc from a CGEventTap that runs on its own thread.
///
/// The chord is modifier-only, so it works while secure input is on. The tap is active, so it can
/// swallow Esc while recording; an active tap needs the Accessibility permission.
final class HotkeyTap: Sendable {
    private struct State {
        var classifier: HotkeyClassifier
        var port: TapPort?
    }

    /// Each event with the time the tap saw it, so a busy consumer does not shift tap vs hold.
    let events: AsyncStream<(event: HotkeyEvent, at: ContinuousClock.Instant)>
    private let continuation: AsyncStream<(event: HotkeyEvent, at: ContinuousClock.Instant)>.Continuation
    private let state: Mutex<State>

    /// `cleanupChord` is the owner's saved choice (`CleanupChord.current`).
    init(cleanupChord: ModifierKeys?) {
        state = Mutex(
            State(classifier: HotkeyClassifier(escapeKeyCode: UInt16(kVK_Escape), cleanupChord: cleanupChord)))
        (events, continuation) = AsyncStream.makeStream(of: (event: HotkeyEvent, at: ContinuousClock.Instant).self)
    }

    /// The owner's cleanup chord; nil turns cleanup dictation off.
    func setCleanupChord(_ chord: ModifierKeys?) {
        state.withLock { $0.classifier.cleanupChord = chord }
    }

    /// Esc is consumed (it does not reach the focused app) only while this is on.
    func setSwallowsEscape(_ swallows: Bool) {
        state.withLock { $0.classifier.swallowsEscape = swallows }
    }

    /// Creates the tap on its own thread. Returns false when the app has no Accessibility
    /// permission yet. The caller waits without blocking its thread.
    func start() async -> Bool {
        await withCheckedContinuation { started in
            startThread { started.resume(returning: $0) }
        }
    }

    private func startThread(reporting started: @escaping @Sendable (Bool) -> Void) {
        let thread = Thread { [self] in
            let mask =
                CGEventMask(1 << CGEventType.flagsChanged.rawValue) | CGEventMask(1 << CGEventType.keyDown.rawValue)
            guard
                let port = CGEvent.tapCreate(
                    tap: .cgSessionEventTap,
                    place: .headInsertEventTap,
                    options: .defaultTap,
                    eventsOfInterest: mask,
                    callback: hotkeyTapCallback,
                    userInfo: Unmanaged.passUnretained(self).toOpaque()
                )
            else {
                started(false)
                return
            }
            state.withLock { $0.port = TapPort(port: port) }
            let source = CFMachPortCreateRunLoopSource(nil, port, 0)
            CFRunLoopAddSource(CFRunLoopGetCurrent(), source, .commonModes)
            CGEvent.tapEnable(tap: port, enable: true)
            started(true)
            CFRunLoopRun()
        }
        thread.name = "kotoba.hotkey-tap"
        thread.qualityOfService = .userInteractive
        thread.start()
    }

    /// Runs on the tap thread for every event; it must return fast or the system disables the tap.
    /// The decisions live in `HotkeyClassifier`; this only converts the CGEvent.
    func handle(_ type: CGEventType, _ event: CGEvent) -> Unmanaged<CGEvent>? {
        let input: KeyInput
        switch type {
        case .tapDisabledByTimeout, .tapDisabledByUserInput:
            if let tap = state.withLock({ $0.port }) {
                CGEvent.tapEnable(tap: tap.port, enable: true)
            }
            input = .tapReenabled(modifiers: Self.modifiers(CGEventSource.flagsState(.combinedSessionState)))
        case .flagsChanged:
            input = .modifiersChanged(Self.modifiers(event.flags))
        case .keyDown:
            input = .keyDown(keyCode: UInt16(truncatingIfNeeded: event.getIntegerValueField(.keyboardEventKeycode)))
        default:
            return Unmanaged.passUnretained(event)
        }
        let decision = state.withLock { $0.classifier.classify(input) }
        let now = ContinuousClock.now
        for hotkey in decision.events {
            continuation.yield((hotkey, now))
        }
        return decision.isSwallowed ? nil : Unmanaged.passUnretained(event)
    }

    private static func modifiers(_ flags: CGEventFlags) -> ModifierKeys {
        var keys: ModifierKeys = []
        if flags.contains(.maskControl) { keys.insert(.control) }
        if flags.contains(.maskAlternate) { keys.insert(.option) }
        if flags.contains(.maskCommand) { keys.insert(.command) }
        if flags.contains(.maskShift) { keys.insert(.shift) }
        if flags.contains(.maskSecondaryFn) { keys.insert(.function) }
        return keys
    }
}

/// CFMachPort is a thread-safe CF object; Swift does not mark it Sendable. Only `tapEnable` uses it off the tap thread.
private struct TapPort: @unchecked Sendable {
    let port: CFMachPort
}

private func hotkeyTapCallback(
    proxy: CGEventTapProxy,
    type: CGEventType,
    event: CGEvent,
    userInfo: UnsafeMutableRawPointer?
) -> Unmanaged<CGEvent>? {
    guard let userInfo else { return Unmanaged.passUnretained(event) }
    return Unmanaged<HotkeyTap>.fromOpaque(userInfo).takeUnretainedValue().handle(type, event)
}
