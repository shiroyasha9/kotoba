import AppKit
import Carbon
import CoreGraphics
import KotobaCore

// MARK: - A CGEvent as the classifier reads it

extension KeyInput {
    /// The owner's key or middle or side button event; nil for any other type.
    init?(_ type: CGEventType, _ event: CGEvent) {
        let modifiers = ModifierKeys(eventFlags: event.flags.rawValue)
        switch type {
        case .flagsChanged: self = .modifiersChanged(modifiers)
        case .keyDown:
            self = .keyDown(
                keyCode: Self.keyCode(event), modifiers: modifiers,
                isRepeat: event.getIntegerValueField(.keyboardEventAutorepeat) != 0)
        case .keyUp: self = .keyUp(keyCode: Self.keyCode(event), modifiers: modifiers)
        case .otherMouseDown: self = .otherMouseDown(button: Self.button(event), modifiers: modifiers)
        case .otherMouseUp: self = .otherMouseUp(button: Self.button(event), modifiers: modifiers)
        case .otherMouseDragged: self = .otherMouseDragged(button: Self.button(event))
        default: return nil
        }
    }

    private static func keyCode(_ event: CGEvent) -> UInt16 {
        UInt16(truncatingIfNeeded: event.getIntegerValueField(.keyboardEventKeycode))
    }

    private static func button(_ event: CGEvent) -> Int {
        Int(event.getIntegerValueField(.mouseEventButtonNumber))
    }
}

// MARK: - The owner's input, for Polish's replace by Backspace

extension HotkeyTap {
    /// A key-down or a middle or side click that reaches an app is the owner's input (`inputCount`); a chord the tap
    /// swallows is not. While Secure Input is on the tap gets no key-downs but still modifier changes, so each of those
    /// counts, as unseen keys may have come with it (0.85 µs a check, `swiftc -O` probe, 2026-10-17).
    func countInput(_ input: KeyInput, _ decision: HotkeyDecision) {
        switch input {
        case .keyDown where !decision.isSwallowed, .otherMouseDown where !decision.isSwallowed: noteInput()
        case .modifiersChanged where IsSecureEventInputEnabled(): noteInput()
        default: break
        }
    }

    func noteInput() {
        inputCount.add(1, ordering: .relaxed)
    }

    /// An event a kotoba install posted. This process's ⌘V (the only posted key with ⌘) marks the paste for
    /// `inputMark`; a key the other install (release or Dev) posted changes the field, so it is input here.
    func posted(_ type: CGEventType, _ event: CGEvent) -> KeyInput {
        guard type == .keyDown else { return .posted }
        if event.getIntegerValueField(.eventSourceUnixProcessID) != Int64(FrontAppObserver.ownProcessID) {
            noteInput()
        } else if event.flags.contains(.maskCommand) {
            inputAtPaste.store(inputCount.load(ordering: .relaxed), ordering: .relaxed)
        }
        return .posted
    }

    /// The front app and window and the owner's input since kotoba's last ⌘V (`DictationPipeline.Ports.inputMark`).
    /// Nil whenever the tap cannot see every key: it is off, a recorder listens, or Secure Input hides the keys.
    func inputMark() -> InputMark? {
        guard isObserving, !IsSecureEventInputEnabled(), let front = FrontAppObserver.current,
            let window = FrontWindow.info(of: front.processID)?[kCGWindowNumber as String] as? Int
        else { return nil }
        let since = inputCount.load(ordering: .relaxed) - inputAtPaste.load(ordering: .relaxed)
        return InputMark(processID: front.processID, window: window, inputSincePaste: since)
    }
}
