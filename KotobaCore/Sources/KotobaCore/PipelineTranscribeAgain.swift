import Foundation

extension DictationPipeline {
    /// History's "Transcribe Again": sends the kept audio of a dictation that has its text again, with `model` (a
    /// route's model, `Transcript.model`) or the owner's choice, and keeps the new text in place of the old one. A
    /// cleanup dictation is cleaned again in its mode. Nothing is pasted or copied and the indicator does not change:
    /// the activity lists the dictation (`PipelineActivity.transcribingAgain`), and the History pane shows its row.
    ///
    /// The answers are billed in the usage ledger either way, as a change to the same dictation, not a new one: no
    /// spoken words, and delivered words that move the dictation's total to the new text's words (zero when the text
    /// is not kept), so Insights counts the dictation and its speaking time once.
    ///
    /// False when nothing changed: the dictation has no text yet (Retry sends it), its audio is gone, it is being sent
    /// or sent again, Polish runs, the request failed, the answer heard no words, its cleanup missed, or the store could
    /// not write the new text. The dictation then keeps its text and its status.
    public func transcribeAgain(_ id: DictationID, model: String? = nil) async -> Bool {
        // Polish writes the text it read before its request: the two never overlap.
        guard !inFlight.contains(id), !transcribingAgain.contains(id), !isPolishing else { return false }
        transcribingAgain.insert(id)
        announceActivity()
        defer {
            transcribingAgain.remove(id)
            announceActivity()
        }
        let stored: DictationRecord?
        do {
            stored = try await ports.store.transcribedRecord(id)
        } catch {
            Log.pipeline.error("Transcribe again: cannot read \(id.rawValue): \(error)")
            return false
        }
        guard var record = stored, record.isAudioKept else { return false }
        let oldWords = record.wordCount ?? 0
        do {
            let transcribed = try await delivery.steps.transcribe(&record, settings: settings, model: model)
            if let mode = record.output.cleanupMode,
                // No paste waits: no deadline, as on a retry.
                let miss = await delivery.steps.clean(
                    transcribed, in: mode, into: &record, settings: settings, deadline: nil)
            {
                throw miss
            }
        } catch {
            Log.pipeline.error("Transcribe again \(id.rawValue) on \(record.model ?? "no answer") failed: \(error)")
            // The text is not kept, but the answers were billed.
            await ports.store.addUsageOrLog(Self.reworded(record.usage, change: 0), of: id)
            return false
        }
        record.usage = Self.reworded(record.usage, change: (record.wordCount ?? 0) - oldWords)
        // Polish rewrote the old text: the new text has not been polished.
        record.polishedText = nil
        return await ports.store.updateOrLog(record) == .written
    }

    /// The answers of one Transcribe Again as ledger entries of a dictation already counted: no spoken words, and the
    /// whole word `change` on the first (the speech answer).
    private static func reworded(_ usage: [UsageEntry], change: Int) -> [UsageEntry] {
        usage.enumerated().map { index, entry in
            var entry = entry
            entry.spokenWords = 0
            entry.deliveredWords = index == 0 ? change : 0
            return entry
        }
    }
}
