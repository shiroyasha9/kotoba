import AppKit
import Carbon
import CoreGraphics
import Foundation
import IOKit
import KotobaCore
import Synchronization

/// Reports the owner's hands-free, push-to-talk, cleanup and Paste Last chords, Esc and Return from a CGEventTap that
/// runs on its own thread.
///
/// A modifier-only chord works while secure input is on. The tap is active, so it can swallow Esc and Return while
/// recording and the key of a key chord; an active tap needs the Accessibility permission. Key-up events go
/// through the tap only while a saved chord has a key, so with modifier-only chords typing makes fewer round trips.
/// Mouse-down events come from `MouseDownMonitors`, not the tap, so no click waits for kotoba.
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
    /// On while the tap runs, is enabled and no recorder listens.
    @MainActor let mouse = MouseDownMonitors()

    /// Starts with the saved chords and follows every later change to them.
    @MainActor
    init(chords: HotkeyChords) {
        state = Mutex(
            State(
                classifier: HotkeyClassifier(
                    handsFreeChord: chords.handsFree, pushToTalkChord: chords.savedPushToTalk,
                    cleanupChord: chords.cleanup, pasteLastChord: chords.pasteLast, isReturnGestureOn: true)))
        (events, continuation) = AsyncStream.makeStream(of: (event: HotkeyEvent, at: ContinuousClock.Instant).self)
        chords.tap = self
        mouse.onMouseDown = { [weak self] in self?.sendMouseDown() }
    }

    /// `isPaused` is on while a shortcut recorder listens: no chord counts. A nil `pushToTalk` is the hands-free chord.
    func setChords(handsFree: Chord, pushToTalk: Chord?, cleanup: Chord?, pasteLast: Chord?, isPaused: Bool) {
        let (runLoop, hasKey) = state.withLock { state -> (TapRunLoop?, Bool) in
            state.classifier.handsFreeChord = handsFree
            state.classifier.pushToTalkChord = pushToTalk
            state.classifier.cleanupChord = cleanup
            state.classifier.pasteLastChord = pasteLast
            state.classifier.isPaused = isPaused
            let hasKey = state.classifier.hasKeyChord
            return (state.tap?.hasKeyUp == hasKey ? nil : state.runLoop, hasKey)
        }
        updateMouse()
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
        updateMouse()
        guard let runLoop else { return }
        CFRunLoopPerformBlock(runLoop.loop, CFRunLoopMode.commonModes.rawValue) { [self] in applyEnabled() }
        CFRunLoopWakeUp(runLoop.loop)
    }

    /// Runs on the tap thread. Off ends a press in progress as if every key went up, so a held chord's recording stops
    /// and nothing waits for a release the tap cannot see. On, the classifier reads the keys held now, as after a
    /// timeout.
    private func applyEnabled() {
        let (tap, isEnabled) = state.withLock { ($0.tap, $0.isEnabled) }
        // Only this thread enables the port, so the call needs no lock; a later change queued another block.
        if let tap {
            CGEvent.tapEnable(tap: tap.port, enable: isEnabled)
        }
        state.withLock { state in
            let keys =
                isEnabled
                ? Self.reenabled(heldChordKey: state.classifier.heldChordKey)
                : .tapReenabled(modifiers: [], isChordKeyDown: false)
            send(state.classifier.classify(keys).events)
        }
    }

    /// A click on the indicator pill: the events of a chord tap, in order with the real chord's.
    func sendTap() {
        state.withLock { send($0.classifier.pillClick()) }
    }

    /// A mouse button went down (`MouseDownMonitors`), on the main thread after the click: during a press not yet
    /// announced it drops the press. Sent under the lock, so the press's own events cannot pass it; a late one, after the
    /// press ended or showed, changes nothing.
    private func sendMouseDown() {
        state.withLock { state in
            guard state.isEnabled else { return }
            send(state.classifier.classify(.mouseDown).events)
        }
    }

    /// Turns the mouse monitors on while the tap runs, is enabled and no recorder listens; nothing observes clicks
    /// otherwise. Each call reads the state when it runs on the main thread, so calls queued in any order end right.
    private func updateMouse() {
        DispatchQueue.main.async { [self] in
            let isOn = state.withLock { $0.tap != nil && $0.isEnabled && !$0.classifier.isPaused }
            MainActor.assumeIsolated { mouse.setOn(isOn) }
        }
    }

    /// Each event with the time the tap saw it; events seen together share one instant. Called under the state lock, so
    /// events from the tap thread and the main thread reach the pipeline in the order the classifier made them.
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
            let hasKey = state.withLock { $0.classifier.hasKeyChord }
            // Before the tap exists, so a `setEnabled` or chord change that comes during `install` is applied after it.
            state.withLock { $0.runLoop = TapRunLoop(loop: CFRunLoopGetCurrent()) }
            guard install(keyUp: hasKey) else {
                state.withLock { $0.runLoop = nil }
                started(false)
                return
            }
            started(true)
            updateMouse()
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
        let (old, isEnabled) = state.withLock { state in
            defer { state.tap = new }
            return (state.tap, state.isEnabled)
        }
        // A `setEnabled` after the read queued a block that applies it.
        CGEvent.tapEnable(tap: port, enable: isEnabled)
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
        // Sent under the lock, so a mouse-down from the main thread (`sendMouseDown`) cannot pass these events.
        let decision = state.withLock { state in
            // An event already queued when `setEnabled` turned the tap off counts for nothing.
            guard state.isEnabled else { return HotkeyDecision.pass }
            let now = ContinuousClock.now
            // A key chord's key-up can be lost (Secure Input takes the keyboard). While one is held, each event
            // checks its key, so the press ends at the next event, not at the next press of the key.
            if let key = state.classifier.heldChordKey, Self.checksHeldKey(input, key),
                !CGEventSource.keyState(.combinedSessionState, key: key)
            {
                send(state.classifier.classify(.chordKeyReleased).events, at: now)
            }
            let decision = state.classifier.classify(input)
            send(decision.events, at: now)
            return decision
        }
        return decision.isSwallowed ? nil : Unmanaged.passUnretained(event)
    }

    /// Every key event but the held key's own key-up, which ends the press by itself.
    private static func checksHeldKey(_ input: KeyInput, _ key: UInt16) -> Bool {
        switch input {
        case .modifiersChanged, .keyDown: true
        case .keyUp(let keyCode, _): keyCode != key
        case .tapReenabled, .chordKeyReleased, .posted, .mouseDown: false
        }
    }

    /// The system disabled the tap (a slow callback, or user input). Turns it on again unless `setEnabled` turned it
    /// off, and returns the keys held now; nil while it stays off.
    private func reenableAfterTimeout() -> KeyInput? {
        let found = state.withLock { state -> (tap: InstalledTap?, chordKey: UInt16?)? in
            state.isEnabled ? (state.tap, state.classifier.heldChordKey) : nil
        }
        guard let found else { return nil }
        if let tap = found.tap {
            CGEvent.tapEnable(tap: tap.port, enable: true)
        }
        return Self.reenabled(heldChordKey: found.chordKey)
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
