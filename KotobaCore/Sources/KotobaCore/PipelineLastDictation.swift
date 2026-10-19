import Foundation

// MARK: - The last dictation again

extension DictationPipeline {
    /// "Paste Last Dictation", from the menu or its chord: pastes the newest delivered dictation again (`pasteAgain`).
    public func pasteLast() async {
        guard isQuiet, !isQuitting else { return }
        do {
            guard let last = try await ports.store.lastDelivered(), let text = last.latestText else { return }
            await pasteAgain(text, of: last.id)
        } catch {
            Log.pipeline.error("Cannot read the last dictation: \(error)")
        }
    }

    /// Pastes `text` of dictation `id` as a dictation does, with no Return (Paste Last, History's "Paste Again"), into
    /// the app in front now. Only between dictations, with none in flight (its paste would replace this text on the
    /// clipboard before the app reads it); the gate checks that again right before the paste. When paste is not
    /// allowed here, the text stays on the clipboard. The pill says so only while no dictation shows.
    public func pasteAgain(_ text: String, of id: DictationID) async {
        // Checked first too, so a paste that cannot go reads no clipboard.
        guard isQuiet, !isQuitting else { return }
        let request = ClipboardPaste.Request(id: id, text: text, kind: .again, app: ports.frontApp())
        switch await paste.run(request, gate: self) {
        case .pasted(let pasted):
            markPasted(text, at: pasted.place)
            if !pasted.isClipboardKept { emitIfQuiet(.clipboardNotKept(id)) }
        case .copied: emitIfQuiet(.copied(id))
        case .skipped: break
        }
    }

    /// "Copy Last Dictation", from the menu or its chord: leaves the newest delivered dictation on the clipboard, with
    /// no restore, and the indicator says so. During a dictation it copies too, and the indicator keeps its state.
    public func copyLast() async {
        do {
            guard let last = try await ports.store.lastDelivered(), let text = last.latestText else { return }
            await paste.copy(text)
            emitIfQuiet(.copied(last.id))
        } catch {
            Log.pipeline.error("Cannot read the last dictation: \(error)")
        }
    }

    /// History's Copy: leaves `text` on the clipboard, with no restore.
    public func copyAgain(_ text: String) async {
        await paste.copy(text)
    }
}
