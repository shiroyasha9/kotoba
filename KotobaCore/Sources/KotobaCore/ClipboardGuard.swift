import Synchronization

/// The owner's clipboard around a paste: a snapshot at the announcement, the transcript written as a transient item,
/// and a restore once the paste target read it, only if nothing else replaced it (docs/spec.md, "Paste").
actor ClipboardGuard {
    /// The clipboard as it was, and its change count at that moment.
    struct Snapshot: Sendable {
        let changeCount: Int
        let contents: PasteboardSnapshot
    }

    /// A snapshot being taken, and when it was ready, for the `snapshotReady` latency mark.
    typealias Pending = Task<(snapshot: Snapshot, readyAt: ContinuousClock.Instant), Never>

    /// A transient write that waits for its restore.
    struct Write: Sendable, Equatable {
        let changeCount: Int
        /// Tells this write's read from an earlier one's, whose read can arrive after this write.
        let number: Int
    }

    /// What the dictation learns when no app read its paste: `isLeftOnClipboard` true when the transcript stays on
    /// the clipboard, false when something replaced it first.
    typealias Unread = @Sendable (_ isLeftOnClipboard: Bool) async -> Void

    /// Set as the Cmd-V goes out. Read at the moment an app reads the text, on that thread, so a read before the
    /// Cmd-V (a clipboard manager that ignores the transient marker) is never taken for the paste target's.
    private final class Posted: Sendable {
        private let value = Mutex(false)

        var isPosted: Bool { value.withLock { $0 } }

        func post() {
            value.withLock { $0 = true }
        }
    }

    /// The latest transient write, its text, and the clipboard it replaced.
    private struct Waiting {
        let write: Write
        let text: String
        let original: PasteboardSnapshot
        let posted: Posted
        let unread: Unread
        /// Ends the wait for the read (`willPaste`); a read or a newer write cancels it.
        var timer: Task<Void, Never>?
    }

    private let pasteboard: any Pasteboard
    /// Runs the restore that a read sets off, so `settle()` waits for it.
    private let work: PendingWork
    private var pending: Waiting? {
        didSet {
            if oldValue?.write != pending?.write { oldValue?.timer?.cancel() }
        }
    }
    private var writes = 0

    init(pasteboard: any Pasteboard, work: PendingWork) {
        self.pasteboard = pasteboard
        self.work = work
    }

    /// Taken at the announcement, while capture runs, because reading promised data can be slow. While an earlier
    /// paste still waits to restore, the pasteboard holds that transcript, so the earlier snapshot is the owner's
    /// clipboard.
    func snapshot() async -> Snapshot {
        let changeCount = await pasteboard.changeCount
        if let pending, pending.write.changeCount == changeCount {
            return Snapshot(changeCount: changeCount, contents: pending.original)
        }
        return Snapshot(changeCount: changeCount, contents: await pasteboard.snapshot())
    }

    /// Writes the transcript as a transient item; the owner's clipboard comes back once the paste target reads it.
    /// If the owner copied something after `snapshot`, that newer clipboard is the one to restore. Nil when there is
    /// nothing to restore: the clipboard was too large to keep (`PasteboardSnapshot.isTooLarge`). An earlier paste
    /// whose Cmd-V went out and that no app read is replaced here: it learns so (`Unread`, not left).
    func writeTransient(_ text: String, over snapshot: Snapshot, unread: @escaping Unread) async -> Write? {
        let isUnchanged = await pasteboard.changeCount == snapshot.changeCount
        let original = isUnchanged ? snapshot.contents : await self.snapshot().contents
        writes += 1
        let number = writes
        let posted = Posted()
        let changeCount = await pasteboard.writeTransient(text) { [work] in
            guard posted.isPosted else {
                Log.pipeline.notice("An app read the transient text before the Cmd-V; it is not the paste target")
                return
            }
            work.track { await self.read(number) }
        }
        if let earlier = pending, earlier.posted.isPosted {
            // Tracked, so this paste does not wait for the earlier dictation's row.
            work.track { await earlier.unread(false) }
        }
        let write = Write(changeCount: changeCount, number: number)
        pending =
            original.isTooLarge
            ? nil : Waiting(write: write, text: text, original: original, posted: posted, unread: unread)
        return pending?.write
    }

    /// The Cmd-V for `write` goes out now: from here a read is the paste target's. When no app reads it by
    /// `deadline`, the paste went nowhere (`readWaitEnded`).
    func willPaste(_ write: Write, readBy deadline: ContinuousClock.Instant) {
        guard pending?.write == write else { return }
        pending?.posted.post()
        pending?.timer = work.schedule(at: deadline) { await self.readWaitEnded(write) }
    }

    /// Leaves `text` on the clipboard for the owner to paste, with no restore.
    func copy(_ text: String) async {
        pending = nil
        _ = await pasteboard.write(text)
    }

    /// The paste target read write `number`: the owner's clipboard comes back, unless something replaced the
    /// transcript since.
    private func read(_ number: Int) async {
        guard let pending, pending.write.number == number else { return }
        self.pending = nil
        await pasteboard.restore(pending.original, ifChangeCount: pending.write.changeCount)
    }

    /// No app read `write` in time, so the paste went nowhere: the transcript stays, as a plain copy the owner can
    /// paste (and clipboard managers keep), and the earlier clipboard is not restored (lead, 2026-10-17). When the
    /// owner copied something since, that stays. Either way the dictation learns it was not pasted.
    func readWaitEnded(_ write: Write) async {
        guard let waiting = pending, waiting.write == write else { return }
        // Called from the timer itself: it is not cancelled with the wait.
        pending?.timer = nil
        pending = nil
        let isLeft = await pasteboard.restore(.plainText(waiting.text), ifChangeCount: write.changeCount)
        await waiting.unread(isLeft)
    }
}
