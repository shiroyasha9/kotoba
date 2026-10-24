import KotobaCore
import SwiftUI

// MARK: - Snapshots

extension ChordRecorder {
    /// The recorder at rest, off, with the fn hint, listening, after a refused chord, and for Paste Last, Copy Last and
    /// Rewrite Last, in a grouped form as on the Shortcuts page.
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
            mouseRows()
            lastRows(chords: chords)
        }
        .formStyle(.grouped)
        .frame(width: 520)
        return [Snapshot(name: "chord-recorder") { NSHostingView(rootView: form) }]
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

    /// A side button for push to talk, the middle button with ⌥ for hands-free, the hint while listening, and a mouse
    /// button refused for cleanup.
    @MainActor
    @ViewBuilder
    private static func mouseRows() -> some View {
        let sideButton = Chord(mouseButton: 3)
        row(
            "Push to talk on a side button",
            ChordRecorder(chords: HotkeyChords(defaults: nil, pushToTalk: sideButton), role: .pushToTalk))
        row(
            "Hands-free on ⌥ and the middle button",
            ChordRecorder(
                chords: HotkeyChords(defaults: nil, handsFree: Chord(modifiers: .option, mouseButton: 2)),
                role: .handsFree))
        row(
            "Push to talk listening",
            ChordRecorder(
                chords: HotkeyChords(defaults: nil), role: .pushToTalk, listener: ChordListener(isListening: true)))
        row(
            "Cleanup on a mouse button",
            ChordRecorder(
                chords: HotkeyChords(defaults: nil), role: .cleanup,
                listener: ChordListener(refused: (sideButton, .mouseButtonOnlyForDictation))))
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
            "Copy last off by a clash",
            ChordRecorder(
                chords: HotkeyChords(defaults: nil, handsFree: Chord(modifiers: .rightCommand)), role: .copyLast))
        row(
            "Copy last clash",
            ChordRecorder(
                chords: pasteLast, role: .copyLast,
                listener: ChordListener(
                    refused: (
                        Chord(modifiers: [.control, .command], keyCode: KeyCode.ansiV),
                        .copyLastSameAs(.pasteLast)
                    ))))
        row("Polish last off", ChordRecorder(chords: chords, role: .polishLast))
        row(
            "Polish last off, push to talk on ⌥",
            ChordRecorder(
                chords: HotkeyChords(defaults: nil, pushToTalk: Chord(modifiers: .option)), role: .polishLast))
        row(
            "Polish last set",
            ChordRecorder(chords: HotkeyChords(defaults: nil, polishLast: optionOne), role: .polishLast))
        row(
            "Polish last clash",
            ChordRecorder(
                chords: chords, role: .polishLast,
                listener: ChordListener(refused: (.defaultCopyLast, .polishLastSameAs(.copyLast)))))
    }

    private static let optionOne = Chord.polishLastSuggestions[0]

    @MainActor
    private static func row(_ title: String, _ recorder: ChordRecorder) -> some View {
        LabeledContent(title) { recorder }
    }
}
