import AppKit
import KotobaCore
import Observation
import SwiftUI

// Custom: AppKit and SwiftUI have no shortcut recorder control.
/// The shortcut recorder for one chord: click, press the chord, and it is saved. A refused chord keeps the old one
/// and shows why. General and onboarding use it.
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
                if role == .cleanup || role == .pasteLast || role == .copyLast, chord != nil {
                    Button("Turn Off", systemImage: "xmark.circle") { save(nil) }
                        .labelStyle(.iconOnly)
                        .buttonStyle(.borderless)
                        .help(role == .cleanup ? "Turn off cleanup dictation" : "Turn off this shortcut")
                }
                if let defaultChord, chord != defaultChord {
                    Button("Reset", systemImage: "arrow.counterclockwise") { save(defaultChord) }
                        .labelStyle(.iconOnly)
                        .buttonStyle(.borderless)
                        .help("Reset to \(defaultChord.title)")
                }
                Button(action: toggle) {
                    Text(caption)
                        .frame(minWidth: Self.captionWidth)
                        .foregroundStyle(listener.isListening ? AnyShapeStyle(.tint) : AnyShapeStyle(.primary))
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

    /// Fits ⌃⌥⇧⌘ and "Press a shortcut", so the button keeps its width while it listens.
    private static let captionWidth: CGFloat = 96

    private var chord: Chord? { chords.chord(role) }

    /// Push to talk's is the hands-free chord. Paste Last has none: it is off until the owner records one.
    private var defaultChord: Chord? {
        switch role {
        case .handsFree: .defaultHandsFree
        case .pushToTalk: chords.handsFree
        case .cleanup: .defaultCleanup
        case .pasteLast: nil
        case .copyLast: .defaultCopyLast
        }
    }

    private var caption: String {
        guard listener.isListening else { return chord?.title ?? "Off" }
        return listener.held.isEmpty ? "Press a shortcut" : Chord(modifiers: listener.held.kinds).title
    }

    /// Why the last recorded chord was refused, or a hint for an fn chord or one that opens the mic briefly. Push to
    /// talk on the hands-free chord leaves the hint to the hands-free line.
    private var note: (text: String, isProblem: Bool)? {
        if let refused = listener.refused {
            return (refused.problem.text(refused.chord, role: role, chords: chords), true)
        }
        guard let chord, chord.keyCode == nil else { return nil }
        if role == .pushToTalk, chords.separatePushToTalk == nil { return nil }
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
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.flagsChanged, .keyDown, .keyUp]) { [weak self] event in
            let input = Self.input(event)
            MainActor.assumeIsolated { self?.handle(input, recorded: recorded) }
            // While listening, no key reaches the window: Return does not press the default button.
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
        case .needsKey, .pasteLastSameAs, .pasteLastIncludes, .copyLastSameAs, .copyLastIncludes:
            return lastText(chord, role: role, chords: chords)
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
        }
    }

    /// The Paste Last and Copy Last problems: `chord` was recorded for `role`, the last-dictation chord or the chord it
    /// clashes with.
    @MainActor
    private func lastText(_ chord: Chord, role: HotkeyChords.Role, chords: HotkeyChords) -> String {
        switch self {
        case .pasteLastSameAs(let other): Self.sameAsText(other, last: .pasteLast, role: role)
        case .copyLastSameAs(let other): Self.sameAsText(other, last: .copyLast, role: role)
        case .pasteLastIncludes(let other):
            Self.includesText(chord, other, last: .pasteLast, role: role, chords: chords)
        case .copyLastIncludes(let other):
            Self.includesText(chord, other, last: .copyLast, role: role, chords: chords)
        default: "Add a key to \(chord.title), for example \(role == .copyLast ? "⌃⌘C" : "⌃⌘V")."
        }
    }

    /// The `last` chord (Paste Last or Copy Last) is the chord of `other`.
    private static func sameAsText(_ other: HotkeyChords.Role, last: HotkeyChords.Role, role: HotkeyChords.Role)
        -> String
    {
        guard role == last else {
            let action = last == .pasteLast ? "paste" : "copy"
            return "This is the shortcut to \(action) the last dictation."
        }
        return "This is the \(name(other)) shortcut."
    }

    /// The `last` chord (Paste Last or Copy Last) holds the modifier-only chord of `other` on the way to its key.
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

// MARK: - Snapshots

extension ChordRecorder {
    /// The recorder at rest, off, with the fn hint, listening, after a refused chord, and for Paste Last and Copy Last, in a grouped
    /// form as in General.
    @MainActor
    static func snapshots() -> [Snapshot] {
        let chords = HotkeyChords(defaults: nil)
        let off = HotkeyChords(defaults: nil, cleanup: nil)
        let fnChords = HotkeyChords(defaults: nil, handsFree: Chord(modifiers: .function))
        let pairChords = HotkeyChords(defaults: nil, handsFree: Chord(modifiers: [.control, .option]))
        let clash = HotkeyChords(
            defaults: nil, handsFree: Chord(modifiers: .function), cleanup: Chord(modifiers: [.control, .option]))
        let spotlight = Chord(modifiers: .command, keyCode: KeyCode.space)
        let form = Form {
            row("At rest", ChordRecorder(chords: chords, role: .handsFree))
            pushToTalkRows(handsFree: pairChords)
            row("Cleanup off", ChordRecorder(chords: off, role: .cleanup))
            row("fn", ChordRecorder(chords: fnChords, role: .handsFree))
            row("Two keys", ChordRecorder(chords: pairChords, role: .handsFree))
            row(
                "Listening",
                ChordRecorder(
                    chords: chords, role: .handsFree,
                    listener: ChordListener(isListening: true, held: [.leftControl, .leftOption])))
            row(
                "Refused",
                ChordRecorder(
                    chords: chords, role: .cleanup, listener: ChordListener(refused: (spotlight, .reserved))))
            row(
                "Clash",
                ChordRecorder(
                    chords: clash, role: .handsFree,
                    listener: ChordListener(refused: (.defaultHandsFree, .dictationIncludesCleanup(.handsFree)))))
            lastRows(chords: chords)
        }
        .formStyle(.grouped)
        .frame(width: 520)
        return [Snapshot(name: "chord-recorder") { Snapshots.hostingView(form) }]
    }

    /// Push to talk on the hands-free chord (no hint of its own), on ⌥ alone with its hint, and refused.
    @MainActor
    @ViewBuilder
    private static func pushToTalkRows(handsFree: HotkeyChords) -> some View {
        row("Push to talk as hands-free", ChordRecorder(chords: handsFree, role: .pushToTalk))
        row(
            "Push to talk on ⌥",
            ChordRecorder(chords: HotkeyChords(defaults: nil, pushToTalk: Chord(modifiers: .option)), role: .pushToTalk)
        )
        row(
            "Push to talk refused",
            ChordRecorder(
                chords: HotkeyChords(defaults: nil), role: .pushToTalk,
                listener: ChordListener(refused: (.defaultCleanup, .sameAsCleanup(.pushToTalk)))))
        row(
            "Push to talk on ⌘",
            ChordRecorder(
                chords: HotkeyChords(defaults: nil), role: .pushToTalk,
                listener: ChordListener(refused: (Chord(modifiers: .command), .commonModifierAlone))))
    }

    /// Paste Last off, set, refused for a clash and for no key; Copy Last at its default and refused for a clash.
    @MainActor
    @ViewBuilder
    private static func lastRows(chords: HotkeyChords) -> some View {
        let controlCommandV = Chord(modifiers: [.control, .command], keyCode: KeyCode.ansiV)
        let pasteLast = HotkeyChords(defaults: nil, pasteLast: controlCommandV)
        let pasteLastClash = Chord(modifiers: [.control, .option, .command], keyCode: KeyCode.ansiV)
        row("Paste last off", ChordRecorder(chords: chords, role: .pasteLast))
        row("Paste last set", ChordRecorder(chords: pasteLast, role: .pasteLast))
        row(
            "Paste last clash",
            ChordRecorder(
                chords: chords, role: .pasteLast,
                listener: ChordListener(refused: (pasteLastClash, .pasteLastIncludes(.handsFree)))))
        row(
            "Paste last without a key",
            ChordRecorder(
                chords: chords, role: .pasteLast,
                listener: ChordListener(refused: (Chord(modifiers: [.control, .command]), .needsKey))))
        row("Copy last at its default", ChordRecorder(chords: chords, role: .copyLast))
        row(
            "Copy last clash",
            ChordRecorder(
                chords: pasteLast, role: .copyLast,
                listener: ChordListener(
                    refused: (
                        Chord(modifiers: [.control, .command], keyCode: KeyCode.ansiV),
                        .copyLastSameAs(.pasteLast)
                    ))))
    }

    @MainActor
    private static func row(_ title: String, _ recorder: ChordRecorder) -> some View {
        LabeledContent(title) { recorder }
    }
}
