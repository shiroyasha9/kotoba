import Foundation

extension DictationPipeline {
    /// History's "Transcribe Again": sends the kept audio of a dictation that has its text again, with `model` (a
    /// route's model, `Transcript.model`) or the owner's choice, and keeps the new text in place of the old one. A
    /// cleanup dictation is cleaned again in its mode. Nothing is pasted or copied and the indicator does not change:
    /// the History pane shows the row. The answer is billed in the usage ledger either way.
    ///
    /// False when nothing changed: the dictation has no text yet (Retry sends it), its audio is gone, it is being sent,
    /// the request failed or the answer heard no words. The dictation then keeps its text and its status.
    public func transcribeAgain(_ id: DictationID, model: String? = nil) async -> Bool {
        guard !inFlight.contains(id) else { return false }
        let stored: DictationRecord?
        do {
            stored = try await ports.store.transcribedRecord(id)
        } catch {
            Log.pipeline.error("Transcribe again: cannot read \(id.rawValue): \(error)")
            return false
        }
        guard var record = stored, !record.isAudioDeleted else { return false }
        do {
            let transcribed = try await delivery.steps.transcribe(&record, settings: settings, model: model)
            if let mode = record.output.cleanupMode {
                // No paste waits: no deadline, as on a retry.
                await delivery.steps.clean(transcribed, in: mode, into: &record, settings: settings, deadline: nil)
            }
        } catch {
            Log.pipeline.error("Transcribe again \(id.rawValue) on \(record.model ?? "no answer") failed: \(error)")
            await bill(record.usage, of: id)
            return false
        }
        return await ports.store.updateOrLog(record)
    }

    /// The answers of a request whose text is not kept were billed all the same.
    private func bill(_ usage: [UsageEntry], of id: DictationID) async {
        guard !usage.isEmpty else { return }
        do {
            try await ports.store.addUsage(usage)
        } catch {
            Log.pipeline.error("Transcribe again \(id.rawValue): cannot bill the answer: \(error)")
        }
    }
}
