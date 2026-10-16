import Carbon
import CoreGraphics
import Foundation
import IOKit
import KotobaCore
import Synchronization

/// Reports the owner's dictation and cleanup chords, Esc and Return from a CGEventTap that runs on its own thread.
///
/// A modifier-only chord works while secure input is on. The tap is active, so it can swallow Esc and Return while
/// recording and the key of a key chord; an active tap needs the Accessibility permission. Key-up events go
/// through the tap only while a saved chord has a key, so with modifier-only chords typing makes fewer round trips.
final class HotkeyTap: Sendable {
    private struct State {
        var classifier: HotkeyClassifier
        var tap: InstalledTap?
        /// The tap thread's run loop, once it runs; a chord change that adds or drops key-up remakes the tap there.
        var runLoop: TapRunLoop?
        /// Off while a development build gives way to the release app (`setEnabled`).
        var isEnabled = true
    }

    /// Each event with the time the tap saw it, so a busy consumer does not shift tap vs hold.
    let events: AsyncStream<(event: HotkeyEvent, at: ContinuousClock.Instant)>
    private let continuation: AsyncStream<(event: HotkeyEvent, at: ContinuousClock.Instant)>.Continuation
    private let state: Mutex<State>

    /// Starts with the saved chords and follows every later change to them.
    @MainActor
    init(chords: HotkeyChords) {
        state = Mutex(
            State(
                classifier: HotkeyClassifier(
                    dictationChord: chords.dictation, cleanupChord: chords.cleanup, isReturnGestureOn: true)))
        (events, continuation) = AsyncStream.makeStream(of: (event: HotkeyEvent, at: ContinuousClock.Instant).self)
        chords.tap = self
    }

    /// `isPaused` is on while a shortcut recorder listens: no chord counts.
    func setChords(dictation: Chord, cleanup: Chord?, isPaused: Bool) {
        let hasKey = dictation.keyCode != nil || cleanup?.keyCode != nil
        let runLoop = state.withLock {
            $0.classifier.dictationChord = dictation
            $0.classifier.cleanupChord = cleanup
            $0.classifier.isPaused = isPaused
            return $0.tap?.hasKeyUp == hasKey ? nil : $0.runLoop
        }
        guard let runLoop else { return }
        CFRunLoopPerformBlock(runLoop.loop, CFRunLoopMode.commonModes.rawValue) { [self] in install(keyUp: hasKey) }
        CFRunLoopWakeUp(runLoop.loop)
    }

    /// While on, Esc and Return are consumed (they do not reach the focused app): Esc cancels, Return submits.
    func setRecordingShown(_ isShown: Bool) {
        state.withLock { $0.classifier.isRecordingShown = isShown }
    }

    /// Off while a development build gives way to the release app (`InstallYield`): the tap stays in place, disabled,
    /// so no key event reaches kotoba and the release app alone hears the chord. The tap thread applies it, as it does
    /// a chord change, so only that thread touches the port and the events stay in order.
    func setEnabled(_ isOn: Bool) {
        let runLoop = state.withLock { state -> TapRunLoop? in
            guard state.isEnabled != isOn else { return nil }
            state.isEnabled = isOn
            return state.runLoop
        }
        guard let runLoop else { return }
        CFRunLoopPerformBlock(runLoop.loop, CFRunLoopMode.commonModes.rawValue) { [self] in applyEnabled() }
        CFRunLoopWakeUp(runLoop.loop)
    }

    /// Runs on the tap thread. Off ends a press in progress as if every key went up, so a held chord's recording stops
    /// and nothing waits for a release the tap cannot see. On, the classifier reads the keys held now, as after a
    /// timeout.
    private func applyEnabled() {
        let events = state.withLock { state in
            if let tap = state.tap {
                CGEvent.tapEnable(tap: tap.port, enable: state.isEnabled)
            }
            let keys =
                state.isEnabled
                ? Self.reenabled(heldChordKey: state.classifier.heldChordKey)
                : .tapReenabled(modifiers: [], isChordKeyDown: false)
            return state.classifier.classify(keys).events
        }
        send(events)
    }

    /// A click on the indicator pill: the events of a chord tap, in order with the real chord's.
    func sendTap() {
        send(state.withLock { $0.classifier.pillClick() })
    }

    /// Each event with the time the tap saw it; events seen together share one instant.
    private func send(_ events: HotkeyEvents, at now: ContinuousClock.Instant = .now) {
        for event in events {
            continuation.yield((event, now))
        }
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
            let hasKey = state.withLock {
                $0.classifier.dictationChord.keyCode != nil || $0.classifier.cleanupChord?.keyCode != nil
            }
            // Before the tap exists, so a `setEnabled` or chord change that comes during `install` is applied after it.
            state.withLock { $0.runLoop = TapRunLoop(loop: CFRunLoopGetCurrent()) }
            guard install(keyUp: hasKey) else {
                state.withLock { $0.runLoop = nil }
                started(false)
                return
            }
            started(true)
            CFRunLoopRun()
        }
        thread.name = "kotoba.hotkey-tap"
        thread.qualityOfService = .userInteractive
        thread.start()
    }

    /// Runs on the tap thread: creates the tap with or without key-up and puts it in place of the old one. On a
    /// failure the old tap stays.
    @discardableResult
    private func install(keyUp: Bool) -> Bool {
        var mask = CGEventMask(1 << CGEventType.flagsChanged.rawValue) | CGEventMask(1 << CGEventType.keyDown.rawValue)
        if keyUp {
            mask |= CGEventMask(1 << CGEventType.keyUp.rawValue)
        }
        guard
            let port = CGEvent.tapCreate(
                tap: .cgSessionEventTap,
                place: .headInsertEventTap,
                options: .defaultTap,
                eventsOfInterest: mask,
                callback: hotkeyTapCallback,
                userInfo: Unmanaged.passUnretained(self).toOpaque()
            ),
            let source = CFMachPortCreateRunLoopSource(nil, port, 0)
        else { return false }
        let new = InstalledTap(port: port, source: source, hasKeyUp: keyUp)
        CFRunLoopAddSource(CFRunLoopGetCurrent(), source, .commonModes)
        let old = state.withLock { state in
            defer { state.tap = new }
            CGEvent.tapEnable(tap: port, enable: state.isEnabled)
            return state.tap
        }
        if let old {
            CGEvent.tapEnable(tap: old.port, enable: false)
            CFRunLoopRemoveSource(CFRunLoopGetCurrent(), old.source, .commonModes)
            CFMachPortInvalidate(old.port)
        }
        return true
    }

    /// Runs on the tap thread for every event; it must return fast or the system disables the tap.
    /// The decisions live in `HotkeyClassifier`; this only converts the CGEvent.
    func handle(_ type: CGEventType, _ event: CGEvent) -> Unmanaged<CGEvent>? {
        let input: KeyInput
        switch type {
        case .tapDisabledByTimeout, .tapDisabledByUserInput:
            guard let reenabled = reenableAfterTimeout() else { return Unmanaged.passUnretained(event) }
            input = reenabled
        case _ where event.getIntegerValueField(.eventSourceUserData) == CGEventPaster.postedEventTag:
            input = .posted
        case .flagsChanged:
            input = .modifiersChanged(ModifierKeys(eventFlags: event.flags.rawValue))
        case .keyDown:
            input = .keyDown(
                keyCode: Self.keyCode(event), modifiers: ModifierKeys(eventFlags: event.flags.rawValue),
                isRepeat: event.getIntegerValueField(.keyboardEventAutorepeat) != 0)
        case .keyUp:
            input = .keyUp(keyCode: Self.keyCode(event), modifiers: ModifierKeys(eventFlags: event.flags.rawValue))
        default:
            return Unmanaged.passUnretained(event)
        }
        let (released, decision) = state.withLock { state in
            // An event already queued when `setEnabled` turned the tap off counts for nothing.
            guard state.isEnabled else { return (HotkeyDecision.pass, HotkeyDecision.pass) }
            // A key chord's key-up can be lost (Secure Input takes the keyboard). While one is held, each event
            // checks its key, so the press ends at the next event, not at the next press of the key.
            var released = HotkeyDecision.pass
            if let key = state.classifier.heldChordKey, Self.checksHeldKey(input, key),
                !CGEventSource.keyState(.combinedSessionState, key: key)
            {
                released = state.classifier.classify(.chordKeyReleased)
            }
            return (released, state.classifier.classify(input))
        }
        let now = ContinuousClock.now
        send(released.events, at: now)
        send(decision.events, at: now)
        return decision.isSwallowed ? nil : Unmanaged.passUnretained(event)
    }

    /// Every key event but the held key's own key-up, which ends the press by itself.
    private static func checksHeldKey(_ input: KeyInput, _ key: UInt16) -> Bool {
        switch input {
        case .modifiersChanged, .keyDown: true
        case .keyUp(let keyCode, _): keyCode != key
        case .tapReenabled, .chordKeyReleased, .posted: false
        }
    }

    /// The system disabled the tap (a slow callback, or user input). Turns it on again unless `setEnabled` turned it
    /// off, and returns the keys held now; nil while it stays off.
    private func reenableAfterTimeout() -> KeyInput? {
        state.withLock { state in
            guard state.isEnabled else { return nil }
            if let tap = state.tap {
                CGEvent.tapEnable(tap: tap.port, enable: true)
            }
            return Self.reenabled(heldChordKey: state.classifier.heldChordKey)
        }
    }

    /// The keys held now, for a tap that missed events while it was disabled.
    private static func reenabled(heldChordKey: UInt16?) -> KeyInput {
        .tapReenabled(
            modifiers: ModifierKeys(eventFlags: CGEventSource.flagsState(.combinedSessionState).rawValue),
            isChordKeyDown: heldChordKey.map { CGEventSource.keyState(.combinedSessionState, key: $0) } ?? false)
    }

    private static func keyCode(_ event: CGEvent) -> UInt16 {
        UInt16(truncatingIfNeeded: event.getIntegerValueField(.keyboardEventKeycode))
    }
}

extension ModifierKeys {
    /// From a CGEvent's or NSEvent's raw flags. The device bits (IOKit's `NX_DEVICE*KEYMASK`) tell left from
    /// right; a flag with no device bit (some synthetic events) counts as the left key. Constant-time.
    init(eventFlags flags: UInt64) {
        // A union chain, not an array literal: the tap callback does not allocate.
        self = Self.sides(
            flags, .maskControl, (NX_DEVICELCTLKEYMASK, .leftControl), (NX_DEVICERCTLKEYMASK, .rightControl))
        formUnion(
            Self.sides(flags, .maskAlternate, (NX_DEVICELALTKEYMASK, .leftOption), (NX_DEVICERALTKEYMASK, .rightOption))
        )
        formUnion(
            Self.sides(flags, .maskShift, (NX_DEVICELSHIFTKEYMASK, .leftShift), (NX_DEVICERSHIFTKEYMASK, .rightShift)))
        formUnion(
            Self.sides(flags, .maskCommand, (NX_DEVICELCMDKEYMASK, .leftCommand), (NX_DEVICERCMDKEYMASK, .rightCommand))
        )
        if flags & CGEventFlags.maskSecondaryFn.rawValue != 0 {
            insert(.function)
        }
    }

    /// `left` and `right` pair a device bit with its key.
    private static func sides(_ flags: UInt64, _ generic: CGEventFlags, _ left: (Int32, Self), _ right: (Int32, Self))
        -> Self
    {
        guard flags & generic.rawValue != 0 else { return [] }
        var keys: Self = []
        if flags & UInt64(right.0) != 0 {
            keys.insert(right.1)
        }
        if flags & UInt64(left.0) != 0 || keys.isEmpty {
            keys.insert(left.1)
        }
        return keys
    }
}

/// CFMachPort and CFRunLoopSource are thread-safe CF objects; Swift does not mark them Sendable. Only the tap thread
/// uses the port and adds and removes the source; other threads only pass the value through the state lock.
private struct InstalledTap: @unchecked Sendable {
    let port: CFMachPort
    let source: CFRunLoopSource
    let hasKeyUp: Bool
}

/// CFRunLoop is thread-safe for `CFRunLoopPerformBlock` and `CFRunLoopWakeUp`, the only calls made from other threads.
private struct TapRunLoop: @unchecked Sendable {
    let loop: CFRunLoop
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
