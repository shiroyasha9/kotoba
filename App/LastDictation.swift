import KotobaCore
import KotobaStorage

/// The last dictation (docs/research/beyond-wispr.md, idea 2): the newest dictation that reached the owner, read from
/// the history. The menu's Last Dictation items send it again through the pipeline, so the clipboard comes back as
/// after a dictation; "Fix Last Dictation…" and the menu flags read it here too.
@MainActor
struct LastDictation {
    enum Action {
        case paste
        /// The raw transcript of a cleanup dictation.
        case pasteWithoutCleanup
        case copy
    }

    let store: HistoryStore
    let pipeline: DictationPipeline

    /// The raw transcript, for a cleanup dictation only; "Paste Last Without Cleanup" shows and pastes this.
    static func rawText(of record: DictationRecord) -> String? {
        record.cleanedText == nil ? nil : record.transcript
    }

    /// The newest delivered dictation; nil when there is none or the history cannot be read.
    func record() async -> DictationRecord? {
        do {
            return try await store.lastDelivered()
        } catch {
            Log.app.error("Cannot read the last dictation: \(error)")
            return nil
        }
    }

    /// The menu has closed when this runs, and a menu bar menu does not take focus, so Cmd-V reaches the app the
    /// owner was in. Paste goes the way of the Paste Last chord (`DictationPipeline.pasteLast`).
    func perform(_ action: Action) {
        Task {
            switch action {
            case .paste:
                await pipeline.pasteLast()
            case .pasteWithoutCleanup:
                if let last = await record(), let raw = Self.rawText(of: last) {
                    await pipeline.pasteAgain(raw, of: last.id)
                }
            case .copy:
                if let text = await record()?.deliveredText { await pipeline.copyAgain(text) }
            }
        }
    }
}
