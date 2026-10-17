import AppKit
import Carbon
import CoreGraphics
import Foundation
import IOKit
import KotobaCore
import Synchronization

/// Reports the owner's hands-free, push-to-talk, cleanup, Paste Last, Copy Last and Polish Last chords, Esc and Return
/// from a CGEventTap that runs on its own thread.
///
/// A modifier-only chord works while secure input is on. The tap is active, so it can swallow Esc and Return while
/// recording and the key of a key chord; an active tap needs the Accessibility permission. Key-up events go
/// through the tap only while a saved chord has a key, so with modifier-only chords typing makes fewer round trips.
/// Copy Last's default chord (⌃⌘C) has a key, so by default every key-up comes here; a key-up that is not swallowed
/// goes back unchanged (`handle`). The callback's own work for one key-up, measured 2026-10-17 in a `swiftc -O` probe
/// (10,000 calls, best of 20, 3 runs): 0.12-0.16 µs in the classifier, 0.35-0.37 µs with the event reads and the lock.
/// Each key-up also makes the window server's trip to this tap and back, as each key-down already does; that trip
/// cannot be measured without synthetic input, so whether typing feels the same is an owner-trial check.
/// Left and right clicks come from `MouseDownMonitors`, not the tap, so no click waits for kotoba. The middle and side
/// buttons go through the tap only while Hands-free or Push to talk is a mouse button: then it swallows that button's
/// down and up, passes its drags as plain moves, reports the other buttons' clicks itself, and the monitors leave them
/// out (`updateMouse`). The callback's own work, measured 2026-10-17 in a `swiftc -O` probe (10,000 calls, best of 20,
/// 3 runs): per middle or side button down or up 0.09-0.12 µs in the classifier, 0.39-0.43 µs with the event reads and
/// the lock; per drag 0.12-0.13 µs. Each such event also makes the window server's trip to this tap and back while a
/// mouse chord is set.
final class HotkeyTap: Sendable {
    private struct State {
        var classifier: HotkeyClassifier
        var tap: InstalledTap?
        /// The tap thread's run loop, once it runs; a chord change that adds or drops key-up or mouse events remakes the
        /// tap there.
        var runLoop: TapRunLoop?
        /// Off while a development build gives way to the release app (`setEnabled`).
        var isEnabled = true

        /// The tap runs, is enabled and no recorder listens: it sees every key and, with the monitors, every click.
        var isObserving: Bool { tap != nil && isEnabled && !classifier.isPaused }
    }

    /// Each event with the time the tap saw it, so a busy consumer does not shift tap vs hold.
    let events: AsyncStream<(event: HotkeyEvent, at: ContinuousClock.Instant)>
    private let continuation: AsyncStream<(event: HotkeyEvent, at: ContinuousClock.Instant)>.Continuation
    /// The system disabled the tap for user input, which an Accessibility revoke can cause: Readiness reads the
    /// grants again (`SetupFlow`). Several in a row come as one.
    let disabledByUserInput: AsyncStream<Void>
    private let disabledContinuation: AsyncStream<Void>.Continuation
    private let state: Mutex<State>
    /// The owner's key-downs that reached an app and clicks in other apps, for Polish's replace by Backspace
    /// (`inputMark`). It also moves each time the tap or the mouse monitors stop observing, so a gap never reads as
    /// "no input".
    let inputCount = Atomic<UInt64>(0)
    /// `inputCount` when the tap saw kotoba's last posted ⌘V: the input since then is counted where the event stream
    /// put it, before or after that paste, however late the pipeline asks.
    let inputAtPaste = Atomic<UInt64>(0)
    /// On while the tap runs, is enabled and no recorder listens.
    @MainActor let mouse = MouseDownMonitors()

    /// Starts with the saved chords and follows every later change to them.
    @MainActor
    init(chords: HotkeyChords) {
        let saved = chords.saved
        state = Mutex(
            State(
                classifier: HotkeyClassifier(
                    handsFreeChord: saved.handsFree, pushToTalkChord: saved.pushToTalk, cleanupChord: saved.cleanup,
                    pasteLastChord: saved.pasteLast, copyLastChord: saved.copyLast, polishLastChord: saved.polishLast,
                    isReturnGestureOn: true)))
        (events, continuation) = AsyncStream.makeStream(of: (event: HotkeyEvent, at: ContinuousClock.Instant).self)
        (disabledByUserInput, disabledContinuation) = AsyncStream.makeStream(bufferingPolicy: .bufferingNewest(1))
        chords.tap = self
        mouse.onMouseDown = { [weak self] in self?.sendMouseDown() }
        mouse.onOtherAppMouseDown = { [weak self] in self?.noteInput() }
    }

    /// `isPaused` is on while a shortcut recorder listens: no chord counts.
    func setChords(_ chords: HotkeyChords.Saved, isPaused: Bool) {
        let runLoop = state.withLock { state -> TapRunLoop? in
            state.classifier.handsFreeChord = chords.handsFree
            state.classifier.pushToTalkChord = chords.pushToTalk
            state.classifier.cleanupChord = chords.cleanup
            state.classifier.pasteLastChord = chords.pasteLast
            state.classifier.copyLastChord = chords.copyLast
            state.classifier.polishLastChord = chords.polishLast
            state.classifier.isPaused = isPaused
            return state.tap?.mask == Self.mask(state.classifier) ? nil : state.runLoop
        }
        updateMouse()
        guard let runLoop else { return }
        // The mask is read when the block runs, so of several quick changes the last one wins.
        CFRunLoopPerformBlock(runLoop.loop, CFRunLoopMode.commonModes.rawValue) { [self] in
            install(state.withLock { Self.mask($0.classifier) })
        }
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
                ? Self.reenabled(heldTrigger: state.classifier.heldTrigger)
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
    /// otherwise. They watch the middle and side buttons only while the tap in place does not. Each call reads the
    /// state when it runs on the main thread, so calls queued in any order end right.
    private func updateMouse() {
        DispatchQueue.main.async { [self] in
            let (isOn, isTapWatchingOthers) = state.withLock { ($0.isObserving, $0.tap?.watchesOtherButtons == true) }
            var mask: NSEvent.EventTypeMask = []
            if isOn {
                mask = MouseDownMonitors.allButtons
                if isTapWatchingOthers { mask.remove(.otherMouseDown) }
            }
            // A click between the tap's change and the monitors' is seen by neither; count it as input.
            let isChanged = MainActor.assumeIsolated { mouse.setMask(mask) }
            if !isOn || isChanged { noteInput() }
        }
    }

    /// On while the tap sees every key (`State.isObserving`).
    var isObserving: Bool { state.withLock { $0.isObserving } }

    /// Each event with the time the tap saw it; events seen together share one instant. Called under the state lock, so
    /// events from the tap thread and the main thread reach the pipeline in the order the classifier made them.
    private func send(_ events: HotkeyEvents, at now: ContinuousClock.Instant = .now) {
        for event in events {
            continuation.yield((event, now))
        }
    }

    /// Creates the tap on its own thread, or makes it again there once the thread runs: after an Accessibility revoke
    /// and a new grant, macOS may send nothing more to the old tap. Returns false when the app has no Accessibility
    /// permission; a tap made again then keeps the old one. The caller waits without blocking its thread.
    func start() async -> Bool {
        guard let runLoop = state.withLock({ $0.runLoop }) else {
            return await withCheckedContinuation { started in
                startThread { started.resume(returning: $0) }
            }
        }
        return await withCheckedContinuation { remade in
            CFRunLoopPerformBlock(runLoop.loop, CFRunLoopMode.commonModes.rawValue) { [self] in
                let isMade = install(state.withLock { Self.mask($0.classifier) })
                // The old tap may have missed key events since the revoke; read the keys held now, as after a timeout.
                if isMade {
                    state.withLock { state in
                        guard state.isEnabled else { return }
                        send(
                            state.classifier.classify(Self.reenabled(heldTrigger: state.classifier.heldTrigger))
                                .events)
                    }
                }
                remade.resume(returning: isMade)
            }
            CFRunLoopWakeUp(runLoop.loop)
        }
    }

    private func startThread(reporting started: @escaping @Sendable (Bool) -> Void) {
        let thread = Thread { [self] in
            let mask = state.withLock { Self.mask($0.classifier) }
            // Before the tap exists, so a `setEnabled` or chord change that comes during `install` is applied after it.
            state.withLock { $0.runLoop = TapRunLoop(loop: CFRunLoopGetCurrent()) }
            guard install(mask) else {
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

    /// The events the tap needs for these chords: key-up only while a chord has a key, the middle and side buttons only
    /// while a dictation chord is one. Never left or right clicks, movement or scrolling.
    private static func mask(_ classifier: HotkeyClassifier) -> CGEventMask {
        var mask = CGEventMask(1 << CGEventType.flagsChanged.rawValue) | CGEventMask(1 << CGEventType.keyDown.rawValue)
        if classifier.hasKeyChord {
            mask |= CGEventMask(1 << CGEventType.keyUp.rawValue)
        }
        if classifier.hasMouseChord {
            mask |= InstalledTap.otherMouseMask
        }
        return mask
    }

    /// Runs on the tap thread: creates the tap for `mask` and puts it in place of the old one. On a failure the old tap
    /// stays.
    @discardableResult
    private func install(_ mask: CGEventMask) -> Bool {
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
        let new = InstalledTap(port: port, source: source, mask: mask)
        // The tap that comes in place of another (or of none) missed the keys in between.
        noteInput()
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
        // The monitors follow whether this tap watches the middle and side buttons.
        updateMouse()
        return true
    }

    /// Runs on the tap thread for every event; it must return fast or the system disables the tap.
    /// The decisions live in `HotkeyClassifier`; this only converts the CGEvent.
    func handle(_ type: CGEventType, _ event: CGEvent) -> Unmanaged<CGEvent>? {
        let input: KeyInput
        switch type {
        case .tapDisabledByTimeout, .tapDisabledByUserInput:
            if type == .tapDisabledByUserInput { disabledContinuation.yield() }
            // Keys went by while the tap was off.
            noteInput()
            guard let reenabled = reenableAfterTimeout() else { return Unmanaged.passUnretained(event) }
            input = reenabled
        case _ where event.getIntegerValueField(.eventSourceUserData) == CGEventPaster.postedEventTag:
            input = posted(type, event)
        default:
            guard let converted = KeyInput(type, event) else { return Unmanaged.passUnretained(event) }
            input = converted
        }
        // Sent under the lock, so a mouse-down from the main thread (`sendMouseDown`) cannot pass these events.
        let decision = state.withLock { state in
            // An event already queued when `setEnabled` turned the tap off counts for nothing.
            guard state.isEnabled else { return HotkeyDecision.pass }
            let now = ContinuousClock.now
            // A key chord's key-up can be lost (Secure Input takes the keyboard), and so can a mouse chord's button-up
            // (the chord changed while it was held, and the new tap watches no button). While one is held, each event
            // checks its key or button, so the press ends at the next event, not at the next press.
            if let trigger = state.classifier.heldTrigger, Self.checksHeld(input, trigger), !Self.isDown(trigger) {
                send(state.classifier.classify(.chordKeyReleased).events, at: now)
            }
            let decision = state.classifier.classify(input)
            send(decision.events, at: now)
            return decision
        }
        countInput(input, decision)
        if decision.passesAsMove {
            // CGEventSetType: apps never got this button's down, so they get a plain move and hover keeps working.
            event.type = .mouseMoved
        }
        return decision.isSwallowed ? nil : Unmanaged.passUnretained(event)
    }

    /// Every key, modifier and button event but the held key's or button's own, which ends the press by itself. Drags
    /// are left out: they come many times a second, and the held button's own drag shows it is down.
    private static func checksHeld(_ input: KeyInput, _ trigger: Chord.Trigger) -> Bool {
        switch input {
        case .modifiersChanged, .keyDown: true
        case .keyUp(let keyCode, _): trigger != .key(keyCode)
        case .otherMouseDown(let button, _), .otherMouseUp(let button, _): trigger != .mouseButton(button)
        case .otherMouseDragged, .tapReenabled, .chordKeyReleased, .posted, .mouseDown: false
        }
    }

    /// Whether the held chord's key or button is down now.
    private static func isDown(_ trigger: Chord.Trigger) -> Bool {
        switch trigger {
        case .key(let key): CGEventSource.keyState(.combinedSessionState, key: key)
        case .mouseButton(let button):
            // An imported C enum takes any raw value; the classifier holds only `Chord.mouseButtons`.
            CGMouseButton(rawValue: UInt32(button)).map {
                CGEventSource.buttonState(.combinedSessionState, button: $0)
            } ?? false
        }
    }

    /// The system disabled the tap (a slow callback, or user input). Turns it on again unless `setEnabled` turned it
    /// off, and returns the keys held now; nil while it stays off.
    private func reenableAfterTimeout() -> KeyInput? {
        let found = state.withLock { state -> (tap: InstalledTap?, trigger: Chord.Trigger?)? in
            state.isEnabled ? (state.tap, state.classifier.heldTrigger) : nil
        }
        guard let found else { return nil }
        if let tap = found.tap {
            CGEvent.tapEnable(tap: tap.port, enable: true)
        }
        return Self.reenabled(heldTrigger: found.trigger)
    }

    /// The keys held now, and whether the held chord's key or button is still down, for a tap that missed events
    /// while it was disabled.
    private static func reenabled(heldTrigger: Chord.Trigger?) -> KeyInput {
        .tapReenabled(
            modifiers: ModifierKeys(eventFlags: CGEventSource.flagsState(.combinedSessionState).rawValue),
            isChordKeyDown: heldTrigger.map(isDown) ?? false)
    }

}

/// CFMachPort and CFRunLoopSource are thread-safe CF objects; Swift does not mark them Sendable. Only the tap thread
/// uses the port and adds and removes the source; other threads only pass the value through the state lock.
private struct InstalledTap: @unchecked Sendable {
    let port: CFMachPort
    let source: CFRunLoopSource
    let mask: CGEventMask

    /// Down, up and drag: the held button's drag becomes a plain move (`HotkeyDecision.passesAsMove`).
    static let otherMouseMask =
        CGEventMask(1 << CGEventType.otherMouseDown.rawValue) | CGEventMask(1 << CGEventType.otherMouseUp.rawValue)
        | CGEventMask(1 << CGEventType.otherMouseDragged.rawValue)

    var watchesOtherButtons: Bool { mask & Self.otherMouseMask != 0 }
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
