import AppKit
import KotobaCore
import Observation
import SwiftUI

// Custom: AppKit and SwiftUI have no shortcut recorder control.
/// The shortcut recorder for one chord: click, press the chord, and it is saved. A refused chord keeps the old one
/// and shows why. The Shortcuts page and onboarding use it.
struct ChordRecorder: View {
    let chords: HotkeyChords
    let role: HotkeyChords.Role
    @State private var listener: ChordListener

    init(chords: HotkeyChords, role: HotkeyChords.Role, listener: ChordListener = ChordListener()) {
        self.chords = chords
        self.role = role
        _listener = State(initialValue: listener)
    }

    var body: some View {
        VStack(alignment: .trailing) {
            // Turn Off and Reset come before the recorder, so every recorder in a column keeps the same trailing edge.
            HStack {
                if role != .handsFree, role != .pushToTalk, chord != nil {
                    Button("Turn Off", systemImage: "xmark.circle") { save(nil) }
                        .labelStyle(.iconOnly)
                        .buttonStyle(.borderless)
                        .help(role == .cleanup ? "Turn off the cleanup shortcut" : "Turn off this shortcut")
                }
                // A default Copy Last that a dictation chord turned off would be refused: the note says why instead.
                if let defaultChord, chord != defaultChord, role != .copyLast || chords.copyLastOffReason == nil {
                    Button("Reset", systemImage: "arrow.counterclockwise") { save(defaultChord) }
                        .labelStyle(.iconOnly)
                        .buttonStyle(.borderless)
                        .help("Reset to \(defaultChord.title)")
                }
                // Rewrite Last is off until the owner records one: one click takes the suggestion.
                if role == .polishLast, chord == nil, !listener.isListening,
                    let suggestion = chords.polishLastSuggestion
                {
                    Button("Use \(suggestion.title)") { save(suggestion) }
                        .buttonStyle(.borderless)
                        .help("Rewrite with \(suggestion.title)")
                }
                Button(action: toggle) {
                    // As wide as the widest caption, so the button keeps its width while it listens.
                    ZStack {
                        ForEach(Self.widestCaptions, id: \.self) { Text($0).hidden() }
                        Text(caption)
                            .foregroundStyle(listener.isListening ? AnyShapeStyle(.tint) : AnyShapeStyle(.primary))
                    }
                }
                .help(
                    listener.isListening ? "Press the new shortcut, or Esc to stop" : "Click to record a new shortcut")
            }
            if let note {
                Text(note.text)
                    .font(.caption)
                    .foregroundStyle(note.isProblem ? AnyShapeStyle(.red) : AnyShapeStyle(.secondary))
                    .multilineTextAlignment(.trailing)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .onDisappear { listener.stop() }
    }

    /// The four modifiers and the listening caption: the button is as wide as the wider of the two.
    private static let widestCaptions = ["⌃⌥⇧⌘", listeningCaption]
    private static let listeningCaption = "Press a shortcut"

    private var chord: Chord? { chords.chord(role) }

    /// Push to talk's is the hands-free chord. Paste Last and Rewrite Last have none: they are off until the owner records
    /// one.
    private var defaultChord: Chord? {
        switch role {
        case .handsFree: .defaultHandsFree
        case .pushToTalk: chords.handsFree
        case .cleanup: .defaultCleanup
        case .pasteLast: nil
        case .copyLast: .defaultCopyLast
        case .polishLast: nil
        }
    }

    private var caption: String {
        guard listener.isListening else { return chord?.title ?? "Off" }
        return listener.held.isEmpty ? Self.listeningCaption : Chord(modifiers: listener.held.kinds).title
    }

    /// Why the last recorded chord was refused, or a hint: a dictation recorder that listens also takes a mouse button,
    /// a mouse button no longer reaches apps, an fn chord or one that opens the mic briefly. Push to talk on the
    /// hands-free chord leaves the hint to the hands-free line.
    private var note: (text: String, isProblem: Bool)? {
        if let refused = listener.refused {
            return (refused.problem.text(refused.chord, role: role, chords: chords), true)
        }
        if listener.isListening, role.isDictation {
            return ("You can also press a middle or side mouse button.", false)
        }
        if role == .copyLast, let reason = chords.copyLastOffReason {
            return (reason.defaultCopyLastText(chords: chords), false)
        }
        if role == .pushToTalk, chords.separatePushToTalk == nil { return nil }
        guard let chord else { return nil }
        switch chord.trigger {
        case .key: return nil
        case .mouseButton: return ("Apps no longer get \(chord.title).", false)
        case nil: break
        }
        if chord.modifiers == .function {
            return ("In Keyboard settings, set fn to \u{201C}Do Nothing\u{201D}.", false)
        }
        if chord.opensMicBriefly {
            let shortcuts = chord.modifiers.kindCount == 1 ? "Shortcuts with" : "Shortcuts that start with"
            return ("\(shortcuts) \(chord.title) open the mic for a moment.", false)
        }
        return nil
    }

    private func toggle() {
        if listener.isListening {
            listener.stop()
        } else {
            listener.start(chords: chords) { save($0) }
        }
    }

    /// Only a recorded chord or a reset can be refused; turning a chord off always works.
    private func save(_ new: Chord?) {
        listener.refused = chords.save(new, as: role).flatMap { problem in new.map { ($0, problem) } }
    }
}

/// Listens to the keys while a recorder is on, through a local event monitor: it sees kotoba's own key window
/// only, needs no permission and exists only while listening. One recorder listens at a time.
@MainActor
@Observable
final class ChordListener {
    private(set) var isListening = false
    /// The modifiers held now.
    private(set) var held: ModifierKeys = []
    /// The last chord the owner recorded that was refused, and why.
    var refused: (chord: Chord, problem: ChordProblem)?

    @ObservationIgnored private var capture = ChordCapture()
    @ObservationIgnored private var monitor: Any?
    @ObservationIgnored private var resignObserver: (any NSObjectProtocol)?
    @ObservationIgnored private var chords: HotkeyChords?
    private static weak var current: ChordListener?

    /// `isListening`, `held` and `refused` are for snapshots; a live listener starts with `start`.
    init(isListening: Bool = false, held: ModifierKeys = [], refused: (chord: Chord, problem: ChordProblem)? = nil) {
        self.isListening = isListening
        self.held = held
        self.refused = refused
    }

    func start(chords: HotkeyChords, recorded: @escaping @MainActor (Chord) -> Void) {
        Self.current?.stop()
        Self.current = self
        self.chords = chords
        chords.isRecording = true
        capture = ChordCapture()
        held = []
        refused = nil
        isListening = true
        let mask: NSEvent.EventTypeMask = [.flagsChanged, .keyDown, .keyUp, .otherMouseDown, .otherMouseUp]
        monitor = NSEvent.addLocalMonitorForEvents(matching: mask) { [weak self] event in
            let input = Self.input(event)
            MainActor.assumeIsolated { self?.handle(input, recorded: recorded) }
            // While listening, no key or middle or side button reaches the window: Return does not press the default
            // button, and a side button does not go back.
            return nil
        }
        resignObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didResignActiveNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.stop() }
        }
    }

    private func handle(_ input: KeyInput, recorded: @MainActor (Chord) -> Void) {
        let outcome = capture.handle(input)
        held = capture.held
        switch outcome {
        case .recorded(let chord):
            stop()
            recorded(chord)
        case .cancelled:
            stop()
        case nil:
            break
        }
    }

    /// The monitor runs on the main thread, outside the actor's view.
    private nonisolated static func input(_ event: NSEvent) -> KeyInput {
        switch event.type {
        case .flagsChanged: .modifiersChanged(ModifierKeys(eventFlags: UInt64(event.modifierFlags.rawValue)))
        case .keyDown: .keyDown(keyCode: event.keyCode, modifiers: [], isRepeat: event.isARepeat)
        case .otherMouseDown: .otherMouseDown(button: event.buttonNumber, modifiers: [])
        case .otherMouseUp: .otherMouseUp(button: event.buttonNumber, modifiers: [])
        default: .keyUp(keyCode: event.keyCode, modifiers: [])
        }
    }

    func stop() {
        guard isListening else { return }
        isListening = false
        held = []
        if let monitor {
            NSEvent.removeMonitor(monitor)
        }
        if let resignObserver {
            NotificationCenter.default.removeObserver(resignObserver)
        }
        monitor = nil
        resignObserver = nil
        chords?.isRecording = false
        chords = nil
    }
}

extension ChordProblem {
    /// Why `chord`, recorded for `role`, was refused, with the fix.
    @MainActor
    func text(_ chord: Chord, role: HotkeyChords.Role, chords: HotkeyChords) -> String {
        switch self {
        case .noModifier: return "Add ⌃, ⌥, ⌘ or fn to \(chord.title)."
        case .commonModifierAlone:
            let kind = Chord(modifiers: chord.modifiers.kinds).title
            guard role == .pushToTalk else {
                return "\(kind) alone is part of many shortcuts. Add a modifier, or use the right \(kind)."
            }
            let held = chord.modifiers.isDisjoint(with: .shift) ? "before shortcuts" : "while you type capitals"
            return "You hold \(kind) \(held). Use ⌥ or ⌃, or the right \(kind)."
        case .commandPair: return "Many app shortcuts start with \(chord.title). Add a third modifier."
        case .reserved: return "macOS uses \(chord.title). Choose another shortcut."
        case .escape: return "Esc cancels a dictation. Choose another shortcut."
        case .sameAsCleanup(let dictation):
            return role == .cleanup ? "This is the \(Self.name(dictation)) shortcut." : "This is the cleanup shortcut."
        case .dictationIncludesCleanup(let dictation):
            let held = role == dictation ? chord : (chords.chord(dictation) ?? chord)
            let cleanup = role == .cleanup ? chord : (chords.cleanup ?? chord)
            return "\(held.title) includes \(cleanup.title), so every dictation would clean up."
        case .mouseButtonOnlyForDictation: return "Only Hands-free and Push to talk can use a mouse button."
        case .needsKey, .pasteLastSameAs, .pasteLastIncludes, .copyLastSameAs, .copyLastIncludes, .polishLastSameAs,
            .polishLastIncludes:
            return lastText(chord, role: role, chords: chords)
        }
    }

    /// Why the default Copy Last chord is off: "⌃⌘C includes right ⌘, the hands-free shortcut, so Copy Last is off."
    @MainActor
    func defaultCopyLastText(chords: HotkeyChords) -> String {
        let copyLast = Chord.defaultCopyLast.title
        switch self {
        case .copyLastIncludes(let other):
            let held = chords.chord(other)?.title ?? ""
            return "\(copyLast) includes \(held), the \(Self.name(other)) shortcut, so Copy Last is off."
        case .copyLastSameAs(let other): return "\(copyLast) is the \(Self.name(other)) shortcut, so Copy Last is off."
        default: return "Copy Last is off."
        }
    }

    /// A shortcut's name in a sentence: "This is the push-to-talk shortcut."
    private static func name(_ role: HotkeyChords.Role) -> String {
        switch role {
        case .handsFree: "hands-free"
        case .pushToTalk: "push-to-talk"
        case .cleanup: "cleanup"
        case .pasteLast: "Paste Last"
        case .copyLast: "Copy Last"
        case .polishLast: "Rewrite Last"
        }
    }

    /// The Paste Last, Copy Last and Rewrite Last problems: `chord` was recorded for `role`, the last-dictation chord or
    /// the chord it clashes with.
    @MainActor
    private func lastText(_ chord: Chord, role: HotkeyChords.Role, chords: HotkeyChords) -> String {
        switch self {
        case .pasteLastSameAs(let other): Self.sameAsText(other, last: .pasteLast, role: role)
        case .copyLastSameAs(let other): Self.sameAsText(other, last: .copyLast, role: role)
        case .pasteLastIncludes(let other):
            Self.includesText(chord, other, last: .pasteLast, role: role, chords: chords)
        case .copyLastIncludes(let other):
            Self.includesText(chord, other, last: .copyLast, role: role, chords: chords)
        case .polishLastSameAs(let other): Self.sameAsText(other, last: .polishLast, role: role)
        case .polishLastIncludes(let other):
            Self.includesText(chord, other, last: .polishLast, role: role, chords: chords)
        default: "Add a key to \(chord.title), for example \(Self.example(for: role))."
        }
    }

    private static func example(for role: HotkeyChords.Role) -> String {
        switch role {
        case .copyLast: Chord.defaultCopyLast.title
        case .polishLast: Chord.polishLastSuggestions[0].title
        default: "⌃⌘V"
        }
    }

    /// The `last` chord (Paste Last, Copy Last or Rewrite Last) is the chord of `other`.
    private static func sameAsText(_ other: HotkeyChords.Role, last: HotkeyChords.Role, role: HotkeyChords.Role)
        -> String
    {
        guard role == last else {
            let action =
                switch last {
                case .pasteLast: "paste"
                case .polishLast: "rewrite"
                default: "copy"
                }
            return "This is the shortcut to \(action) the last dictation."
        }
        return "This is the \(name(other)) shortcut."
    }

    /// The `last` chord (Paste Last, Copy Last or Rewrite Last) holds the modifier-only chord of `other` on the way to its
    /// key.
    @MainActor
    private static func includesText(
        _ chord: Chord, _ other: HotkeyChords.Role, last: HotkeyChords.Role, role: HotkeyChords.Role,
        chords: HotkeyChords
    ) -> String {
        let lastChord = role == last ? chord : (chords.chord(last) ?? chord)
        let held = role == last ? (chords.chord(other) ?? chord) : chord
        return "\(lastChord.title) includes \(held.title), so it would start a dictation."
    }
}
