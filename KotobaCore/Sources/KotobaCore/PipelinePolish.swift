import Foundation

extension DictationPipeline {
    /// "Polish Last Dictation", from the menu or its chord (docs/spec.md, "Polish and View Changes"): rewrites the
    /// newest delivered dictation's latest text (`DictationRecord.latestText`) and pastes the rewrite in place of the old
    /// text, selected or deleted by Backspace (`PolishPlacement`), else leaves it on the clipboard. Only between dictations
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
        // Another app in front: a paste there could land in the wrong field.
        let isSameApp = front == nil || ports.frontApp()?.processID == front?.processID
        switch isSameApp ? await put(polished, replacing: text, of: record) : .unsafe {
        case .pasted(let result):
            return result.state(of: record.id, pasted: .polished(record.id, isReplaced: true))
        case .unsafe:
            await clipboard.copy(polished)
            return .polished(record.id, isReplaced: false)
        case .overtaken:
            return nil
        }
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
        switch await put(original, replacing: polished, of: record) {
        case .pasted(let result):
            return result.state(of: id, pasted: .idle)
        case .unsafe:
            await clipboard.copy(original)
            return .copied(id)
        case .overtaken:
            return nil
        }
    }

    private enum Put {
        case pasted(PasteResult)
        /// No safe way to replace the old text: the clipboard gets the new one.
        case unsafe
        /// A dictation came while the request and the selection took their time: it wins, nothing more happens.
        case overtaken
    }

    /// Pastes `new` in place of `old`, the text of `record` that kotoba pasted: over the selection when the selector
    /// finds `old`, else after Backspaces when nothing changed since that paste (`PolishPlacement`).
    private func put(_ new: String, replacing old: String, of record: DictationRecord) async -> Put {
        guard await !isOvertaken(record.id) else { return .overtaken }
        let selection = await ports.selector?.select(old, in: record.app) ?? .untouched
        // The selection took its time: a dictation since then must not find the old text selected.
        guard await !isOvertaken(record.id) else {
            if selection == .selected { await ports.selector?.restoreSelection() }
            return .overtaken
        }
        switch PolishPlacement.choose(
            replacing: old, selection: selection, lastPaste: lastPaste, now: ports.inputMark())
        {
        case .overSelection:
            break
        case .backspaces(let count):
            do {
                try await ports.paster.sendBackspaces(count)
            } catch {
                Log.pipeline.error("Polish: Backspace not allowed: \(error)")
                return .unsafe
            }
        case .clipboard:
            Log.pipeline.info("Polish: no safe way to replace the text; it goes to the clipboard")
            return .unsafe
        }
        return .pasted(await pasteThroughClipboard(new, of: record.id))
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

    /// Pastes `text` of dictation `id` through the clipboard guard, as a dictation does, with no Return: the clipboard
    /// comes back once the app read it, and a paste no app read is left on the clipboard (`ClipboardGuard`).
    func pasteThroughClipboard(_ text: String, of id: DictationID) async -> PasteResult {
        let write = await clipboard.paste(
            text, over: await clipboard.snapshot(), readBy: ports.clock.now + settings.readWait,
            beforeSend: { await self.takePasteTarget(for: id) },
            unread: { await self.pasteWentUnread(text, of: id, marksRow: false, isLeftOnClipboard: $0) })
        let target = pasteTargets.removeValue(forKey: id)
        guard let write else { return .copied }
        markPasted(text, at: target)
        return write.isClipboardKept ? .pasted : .clipboardNotKept
    }

    /// Where the owner is just before a ⌘V, so a Cmd-Tab or a click right after it cannot become the paste's place;
    /// nil while Polish is off, as nothing reads it then. One window list read on the paste path: 0.2 ms p50, 0.5 ms
    /// p90; the first in a process takes 20-40 ms, and the indicator's first key-down already pays it.
    func pasteTarget() -> InputMark? {
        ports.polisher == nil ? nil : ports.inputMark()
    }

    func takePasteTarget(for id: DictationID) {
        pasteTargets[id] = pasteTarget()
    }

    /// Remembers `text` as the last paste, at the place read before its ⌘V.
    func markPasted(_ text: String, at target: InputMark?) {
        lastPaste = target.map { LastPaste(text: text, mark: $0) }
    }
}
