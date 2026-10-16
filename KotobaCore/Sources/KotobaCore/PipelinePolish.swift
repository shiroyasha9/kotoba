import Foundation

extension DictationPipeline {
    /// "Polish Last Dictation", from the menu or its chord (docs/spec.md, "Polish and View Changes"): rewrites the
    /// newest delivered dictation's latest text (`DictationRecord.latestText`) and pastes the rewrite, over the old text
    /// when the selector finds it unchanged in the focused field, else at the insertion point. Only between dictations
    /// and not while History sends one again; a dictation that starts during the request wins, and History keeps the
    /// rewrite with no paste. A failed, cut or late answer pastes nothing. Every answer is billed as a `polish` entry,
    /// with no words.
    public func polishLast() async {
        guard isQuiet, transcribingAgain.isEmpty, let polisher = ports.polisher else { return }
        isPolishing = true
        emit(.polishing)
        // An LLM's rewrite is not the owner's edit: the learning session of the last paste ends here.
        await ports.readback?.dictationStarted()
        let outcome = await polish(with: polisher, front: ports.frontApp())
        isPolishing = false
        finishPolish(showing: outcome)
    }

    /// The Polished pill's Undo: selects the polished text in the field and pastes the text from before that Polish
    /// (an earlier polish, or the dictation's own text); when the polished text is no longer there as pasted, the old
    /// text goes to the clipboard. History goes back to the text from before either way.
    public func undoPolish(_ id: DictationID) async {
        guard isQuiet, transcribingAgain.isEmpty else { return }
        isPolishing = true
        announceActivity()
        let outcome = await revertPolish(of: id)
        isPolishing = false
        finishPolish(showing: outcome)
    }

    private func finishPolish(showing outcome: DictationState?) {
        announceActivity()
        resumeQuietWaiters()
        // A dictation that started meanwhile shows its own state.
        guard let outcome, recording == nil, paused == nil, inFlight.isEmpty else { return }
        emit(outcome)
    }

    /// The outcome the pill shows; nil when a dictation came during the request.
    private func polish(with polisher: any TextPolisher, front: FrontApp?) async -> DictationState? {
        guard let record = await lastDelivered(), let text = record.latestText, !text.isEmpty else {
            return .polishFailed(.nothingToPolish)
        }
        let answer: PolishedText
        switch await polisherAnswer(from: polisher, to: text, for: record) {
        case .answered(.success(let polished)):
            answer = polished
        case .answered(.failure(let error)):
            Log.pipeline.error("Polish \(record.id.rawValue) failed: \(error)")
            return .polishFailed((error as? ProviderError)?.setupItem.map(PolishFailure.needsSetup) ?? .failed)
        case .tooSlow:
            Log.pipeline.error("Polish \(record.id.rawValue) passed its deadline")
            return .polishFailed(.tooSlow)
        }
        let usage = [Self.usage(of: answer, for: record.id, app: record.app, at: ports.clock.date)]
        let polished = answer.text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard answer.isComplete, !polished.isEmpty else {
            Log.pipeline.error("Polish \(record.id.rawValue) answered \(answer.isComplete ? "no words" : "in part")")
            await ports.store.addUsageOrLog(usage, of: record.id)
            return .polishFailed(answer.isComplete ? .failed : .cutOff)
        }
        guard await ports.store.setPolishedTextOrLog(polished, of: record.id, usage: usage) else { return nil }
        lastPolish = (record.id, earlier: record.polishedText)
        if let front, ports.frontApp()?.processID != front.processID {
            // Another app came to the front: a paste there could land in the wrong field.
            await clipboard.copy(polished)
            return .copied(record.id)
        }
        let isReplaced = await ports.selector?.select(text, in: record.app) ?? false
        // The answer and the selection both took time: a dictation since then pastes first.
        guard await !isOvertaken(record.id) else { return nil }
        return await pasteThroughClipboard(polished).state(
            of: record.id, pasted: .polished(record.id, isReplaced: isReplaced))
    }

    private func revertPolish(of id: DictationID) async -> DictationState? {
        guard let record = await lastDelivered(), record.id == id, let polished = record.polishedText else {
            return nil
        }
        let earlier = lastPolish?.id == id ? lastPolish?.earlier : nil
        guard let original = earlier ?? record.deliveredText,
            await ports.store.setPolishedTextOrLog(earlier, of: id, usage: [])
        else { return nil }
        lastPolish = nil
        guard await ports.selector?.select(polished, in: record.app) == true, await !isOvertaken(id) else {
            await clipboard.copy(original)
            return .copied(id)
        }
        return await pasteThroughClipboard(original).state(of: id, pasted: .idle)
    }

    /// A dictation came since Polish began: one records, waits in its Undo window or is sent, or one newer than `id`
    /// reached the owner. Its text is now where Polish would paste.
    private func isOvertaken(_ id: DictationID) async -> Bool {
        guard recording == nil, paused == nil, inFlight.isEmpty else { return true }
        return await lastDelivered()?.id != id
    }

    private func lastDelivered() async -> DictationRecord? {
        do {
            return try await ports.store.lastDelivered()
        } catch {
            Log.pipeline.error("Polish: cannot read the last dictation: \(error)")
            return nil
        }
    }

    /// The polisher's answer, or `.tooSlow` when `Settings.polishDeadline` passes first on the pipeline clock. A late
    /// answer was billed, so its cost goes to the ledger when it comes.
    private func polisherAnswer(from polisher: any TextPolisher, to text: String, for record: DictationRecord) async
        -> Deadlined<PolishedText>
    {
        let request: @Sendable () async throws -> PolishedText = { try await polisher.polish(text) }
        let (store, clock, id, app) = (ports.store, ports.clock, record.id, record.app)
        return await work.answer(to: request, within: settings.polishDeadline, on: clock) { late in
            await store.addUsageOrLog([Self.usage(of: late, for: id, app: app, at: clock.date)], of: id)
        }
    }

    /// Polish's ledger entry: its cost, with no words, so Insights still counts the dictation once.
    private static func usage(of answer: PolishedText, for id: DictationID, app: DictationApp?, at time: Date)
        -> UsageEntry
    {
        UsageEntry(
            time: time, dictation: id, kind: .polish, model: answer.model, deliveredWords: 0, cost: answer.cost,
            app: app)
    }

    enum PasteResult {
        case pasted
        /// Pasted, but the clipboard before it was too large to keep, so it is not restored.
        case clipboardNotKept
        /// Paste was not allowed: the text is on the clipboard.
        case copied

        /// What the pill shows for a paste of dictation `id`: `pasted` when it went as planned.
        func state(of id: DictationID, pasted: DictationState) -> DictationState {
            switch self {
            case .pasted: pasted
            case .clipboardNotKept: .clipboardNotKept(id)
            case .copied: .copied(id)
            }
        }
    }

    /// Pastes `text` through the clipboard guard, as a dictation does, with no Return, and restores the clipboard
    /// after `Settings.restoreDelay`.
    func pasteThroughClipboard(_ text: String) async -> PasteResult {
        let write = await clipboard.writeTransient(text, over: await clipboard.snapshot())
        do {
            try await ports.paster.sendPaste()
        } catch {
            Log.pipeline.error("Paste not allowed, the text is left on the clipboard: \(error)")
            await clipboard.copy(text)
            return .copied
        }
        guard let write else { return .clipboardNotKept }
        work.schedule(at: ports.clock.now + settings.restoreDelay) { await self.clipboard.restore(after: write) }
        return .pasted
    }
}
