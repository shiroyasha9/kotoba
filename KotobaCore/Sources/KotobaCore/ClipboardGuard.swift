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

    private let pasteboard: any Pasteboard
    /// Runs the restore that a read sets off, so `settle()` waits for it.
    private let work: PendingWork
    /// The latest transient write, its text, and the clipboard it replaced.
    private struct Waiting {
        let write: Write
        let text: String
        let original: PasteboardSnapshot
        /// Ends the wait for the read (`leaveUnread`); a read or a newer write cancels it.
        var timer: Task<Void, Never>?
    }

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

    /// Writes the transcript as a transient item; the owner's clipboard comes back once an app reads it. If the owner
    /// copied something after `snapshot`, that newer clipboard is the one to restore. Nil when there is nothing to
    /// restore: the clipboard was too large to keep (`PasteboardSnapshot.isTooLarge`).
    func writeTransient(_ text: String, over snapshot: Snapshot) async -> Write? {
        let isUnchanged = await pasteboard.changeCount == snapshot.changeCount
        let original = isUnchanged ? snapshot.contents : await self.snapshot().contents
        writes += 1
        let number = writes
        let changeCount = await pasteboard.writeTransient(text) { [work] in
            work.track { await self.read(number) }
        }
        let write = Write(changeCount: changeCount, number: number)
        pending = original.isTooLarge ? nil : Waiting(write: write, text: text, original: original)
        return pending?.write
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

    /// After the Cmd-V: when no app read `write` by `deadline`, `unread` runs (`readWaitEnded`). A read first, or a
    /// newer write, cancels the wait, so a paste that went in leaves no timer behind.
    func leaveUnread(
        _ write: Write, at deadline: ContinuousClock.Instant, unread: @escaping @Sendable () async -> Void
    ) {
        guard pending?.write == write else { return }
        pending?.timer = work.schedule(at: deadline) {
            guard await self.readWaitEnded(write) else { return }
            await unread()
        }
    }

    /// No app read `write` in time, so the paste went nowhere: the transcript stays, as a plain copy the owner can
    /// paste (and clipboard managers keep), and the earlier clipboard is not restored (lead, 2026-10-17). True when
    /// the transcript was still there to keep; false when it was read or replaced.
    func readWaitEnded(_ write: Write) async -> Bool {
        guard let pending, pending.write == write else { return false }
        // Called from the timer itself: it is not cancelled with the wait.
        self.pending?.timer = nil
        self.pending = nil
        return await pasteboard.restore(.plainText(pending.text), ifChangeCount: write.changeCount)
    }
}
