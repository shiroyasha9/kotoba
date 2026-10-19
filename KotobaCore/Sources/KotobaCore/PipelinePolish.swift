import Foundation

extension DictationPipeline {
    /// "Polish Last Dictation", from the menu or its chord (docs/spec.md, "Polish and View Changes"): rewrites the
    /// newest delivered dictation's latest text (`DictationRecord.latestText`) and pastes the rewrite in place of the old
    /// text, selected or deleted by Backspace (`PolishPlacement`), else leaves it on the clipboard. Only between dictations
    /// and not while History sends one again; a dictation that starts during the request wins, and History keeps the
    /// rewrite with no paste. A failed, cut or late answer pastes nothing. Every answer is billed as a `polish` entry,
    /// with no words.
    public func polishLast() async {
        // Only between dictations and while History sends none again (`LiveDictations.begin`).
        guard let polisher = ports.polisher, live.begin(.polish) else { return }
        emit(.polishing)
        // An LLM's rewrite is not the owner's edit: the learning session of the last paste ends here.
        await ports.readback?.dictationStarted()
        let outcome = await polish(with: polisher, front: ports.frontApp())
        finishPolish(showing: outcome)
    }

    /// The Polished pill's Undo: selects the polished text in the field and pastes the text from before that Polish
    /// (an earlier polish, or the dictation's own text); when the polished text is no longer there as pasted, the old
    /// text goes to the clipboard. History goes back to the text from before either way.
    public func undoPolish(_ id: DictationID) async {
        guard live.begin(.polish) else { return }
        let outcome = await revertPolish(of: id, front: ports.frontApp())
        finishPolish(showing: outcome)
    }

    private func finishPolish(showing outcome: DictationState?) {
        live.end(.polish)
        // A dictation that started meanwhile shows its own state.
        guard let outcome, !live.isDictationLive else { return }
        emit(outcome)
    }

    /// The outcome the pill shows; nil when a dictation came during the request.
    private func polish(with polisher: any TextPolisher, front: FrontApp?) async -> DictationState? {
        guard let record = await lastDelivered(), let text = record.latestText, !text.isEmpty else {
            return .polishFailed(.nothingToPolish)
        }
        let answer: RewrittenText
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
        switch await put(polished, replacing: text, of: record, for: front) {
        case .pasted(let pasted):
            return pasted.isClipboardKept ? .polished(record.id, isReplaced: true) : .clipboardNotKept(record.id)
        case .copied:
            return .polished(record.id, isReplaced: false)
        case .skipped:
            return nil
        }
    }

    private func revertPolish(of id: DictationID, front: FrontApp?) async -> DictationState? {
        guard let record = await lastDelivered(), record.id == id, let polished = record.polishedText else {
            return nil
        }
        let earlier = lastPolish?.id == id ? lastPolish?.earlier : nil
        guard let original = earlier ?? record.deliveredText,
            await ports.store.setPolishedTextOrLog(earlier, of: id, usage: [])
        else { return nil }
        lastPolish = nil
        switch await put(original, replacing: polished, of: record, for: front) {
        case .pasted(let pasted):
            return pasted.isClipboardKept ? .idle : .clipboardNotKept(id)
        case .copied:
            return .copied(id)
        case .skipped:
            return nil
        }
    }

    /// Pastes `new` in place of `old`, the text of `record` that kotoba pasted, into `front`: over the selection when
    /// the selector finds `old`, else after Backspaces when nothing changed since that paste (`PolishPlacement`); else
    /// the clipboard gets it. Skipped when a dictation came while the request and the selection took their time: it
    /// wins, nothing more happens.
    private func put(_ new: String, replacing old: String, of record: DictationRecord, for front: FrontApp?) async
        -> ClipboardPaste.Outcome
    {
        guard await !isOvertaken(record.id) else { return .skipped }
        // Another app in front: a paste there could land in the wrong field, so no field is touched.
        guard !paste.isFrontAppChanged(from: front) else {
            await paste.copy(new)
            return .copied
        }
        let selection = await ports.selector?.select(old, in: record.app) ?? .untouched
        // The selection took its time: a dictation since then must not find the old text selected.
        guard await !isOvertaken(record.id) else {
            if selection == .selected { await ports.selector?.restoreSelection() }
            return .skipped
        }
        let now = ports.inputMark()
        guard let backspaces = backspaces(replacing: old, selection: selection, now: now) else {
            Log.pipeline.info("Polish: no safe way to replace the text; it goes to the clipboard")
            await paste.copy(new)
            return .copied
        }
        let request = ClipboardPaste.Request(
            id: record.id, text: new, kind: .polish(backspaces: backspaces, at: now), app: front)
        let outcome = await paste.run(request, gate: self)
        switch outcome {
        case .pasted(let pasted): markPasted(new, at: pasted.place)
        case .copied: break
        // kotoba quits, or a dictation came after the selection: the field gets its selection back.
        case .skipped: if selection == .selected { await ports.selector?.restoreSelection() }
        }
        return outcome
    }

    /// How many Backspaces delete `old` before the paste (0 over the selection); nil when no way is safe.
    private func backspaces(replacing old: String, selection: SelectionResult, now: InputMark?) -> Int? {
        switch PolishPlacement.choose(replacing: old, selection: selection, lastPaste: lastPaste, now: now) {
        case .overSelection: 0
        case .backspaces(let count): count
        case .clipboard: nil
        }
    }

    /// A dictation came since Polish began: one records, waits in its Undo window or is sent, or one newer than `id`
    /// reached the owner. Its text is now where Polish would paste.
    private func isOvertaken(_ id: DictationID) async -> Bool {
        guard !live.isDictationLive else { return true }
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
        -> Deadlined<RewrittenText>
    {
        let request: @Sendable () async throws -> RewrittenText = { try await polisher.polish(text) }
        let (store, clock, id, app) = (ports.store, ports.clock, record.id, record.app)
        return await work.answer(to: request, within: settings.polishDeadline, on: clock) { late in
            await store.addUsageOrLog([Self.usage(of: late, for: id, app: app, at: clock.date)], of: id)
        }
    }

    /// Polish's ledger entry: its cost, with no words, so Insights still counts the dictation once.
    private static func usage(of answer: RewrittenText, for id: DictationID, app: DictationApp?, at time: Date)
        -> UsageEntry
    {
        UsageEntry(
            time: time, dictation: id, kind: .polish, model: answer.model, deliveredWords: 0, cost: answer.cost,
            app: app)
    }

    /// Remembers `text` as the last paste, at the place read before its ⌘V.
    func markPasted(_ text: String, at target: InputMark?) {
        lastPaste = target.map { LastPaste(text: text, mark: $0) }
    }
}
