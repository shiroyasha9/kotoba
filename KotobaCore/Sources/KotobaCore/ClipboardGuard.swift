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
        /// The clipboard before it was kept, so it comes back after the read; false when it was too large.
        let isClipboardKept: Bool
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
        /// An app read the text before the Cmd-V went out.
        var isReadEarly = false
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
    /// A write read early while its `writeTransient` was still on its way, before `pending` held it.
    private var earlyReadNumber: Int?
    private let clock: any PipelineClock

    /// A read before the Cmd-V (a clipboard manager that ignores the markers) takes the one read signal, so the
    /// target's own read cannot be seen: the clipboard comes back this long after the Cmd-V, the rule before the read
    /// signal (Jot and FreeFlow use 1 s too).
    static let earlyReadRestoreDelay = Duration.seconds(1)

    init(pasteboard: any Pasteboard, work: PendingWork, clock: any PipelineClock) {
        self.pasteboard = pasteboard
        self.work = work
        self.clock = clock
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
    /// If the owner copied something after `snapshot`, that newer clipboard is the one to restore; one too large to
    /// keep (`PasteboardSnapshot.isTooLarge`) is not restored (`Write.isClipboardKept`), but the read is still waited
    /// for. An earlier paste whose Cmd-V went out and that no app read is replaced here: it learns so (`Unread`, not
    /// left).
    func writeTransient(_ text: String, over snapshot: Snapshot, unread: @escaping Unread) async -> Write {
        let isUnchanged = await pasteboard.changeCount == snapshot.changeCount
        let original = isUnchanged ? snapshot.contents : await self.snapshot().contents
        writes += 1
        let number = writes
        let posted = Posted()
        let changeCount = await pasteboard.writeTransient(text) { [work] in
            // Read here, at the moment of the read: the hop to the actor comes later.
            let isAfterPaste = posted.isPosted
            work.track { await self.read(number, isAfterPaste: isAfterPaste) }
        }
        // An early read took the earlier one's signal: it was probably pasted, so it is not reported.
        if let earlier = pending, earlier.posted.isPosted, !earlier.isReadEarly {
            // Tracked, so this paste does not wait for the earlier dictation's row.
            work.track { await earlier.unread(false) }
        }
        let write = Write(changeCount: changeCount, number: number, isClipboardKept: !original.isTooLarge)
        pending = Waiting(write: write, text: text, original: original, posted: posted, unread: unread)
        pending?.isReadEarly = earlyReadNumber == number
        earlyReadNumber = nil
        return write
    }

    /// The Cmd-V for `write` goes out now: from here a read is the paste target's. When no app reads it by
    /// `deadline`, the paste went nowhere (`readWaitEnded`). After an early read, the clipboard comes back
    /// `earlyReadRestoreDelay` after this.
    func willPaste(_ write: Write, readBy deadline: ContinuousClock.Instant) {
        guard let waiting = pending, waiting.write == write else { return }
        waiting.posted.post()
        if waiting.isReadEarly {
            restoreSoon(write)
        } else {
            pending?.timer = work.schedule(at: deadline) { await self.readWaitEnded(write) }
        }
    }

    /// Leaves `text` on the clipboard for the owner to paste, with no restore.
    func copy(_ text: String) async {
        pending = nil
        _ = await pasteboard.write(text)
    }

    /// An app read write `number`. After the Cmd-V it is the paste target: the owner's clipboard comes back, unless
    /// something replaced the transcript since. Before it, it is a clipboard manager that ignores the markers: the
    /// target's read cannot be seen now, so the clipboard comes back soon after the Cmd-V instead, and the text is not
    /// taken for unread.
    private func read(_ number: Int, isAfterPaste: Bool) async {
        guard let waiting = pending, waiting.write.number == number else {
            // The write is still on its way (`writeTransient` waits on the pasteboard): it takes this early read.
            if !isAfterPaste, number == writes { earlyReadNumber = number }
            return
        }
        guard isAfterPaste else {
            let delay = Self.earlyReadRestoreDelay
            Log.pipeline.notice("An app read the transient text before the Cmd-V; the restore follows it by \(delay)")
            pending?.isReadEarly = true
            if waiting.posted.isPosted { restoreSoon(waiting.write) }
            return
        }
        pending = nil
        await restoreOriginal(of: waiting)
    }

    private func restoreSoon(_ write: Write) {
        pending?.timer?.cancel()
        pending?.timer = work.schedule(at: clock.now + Self.earlyReadRestoreDelay) {
            await self.restoreAfterEarlyRead(write)
        }
    }

    private func restoreAfterEarlyRead(_ write: Write) async {
        guard let waiting = takePending(write) else { return }
        await restoreOriginal(of: waiting)
    }

    /// Ends the wait for `write`, from its own timer: the timer is not cancelled with it. Nil when it no longer waits.
    private func takePending(_ write: Write) -> Waiting? {
        guard let waiting = pending, waiting.write == write else { return nil }
        pending?.timer = nil
        pending = nil
        return waiting
    }

    private func restoreOriginal(of waiting: Waiting) async {
        guard waiting.write.isClipboardKept else { return }
        await pasteboard.restore(waiting.original, ifChangeCount: waiting.write.changeCount)
    }

    /// No app read `write` in time, so the paste went nowhere: the transcript stays, as a plain copy the owner can
    /// paste (and clipboard managers keep), and the earlier clipboard is not restored (lead, 2026-10-17). When the
    /// owner copied something since, that stays. Either way the dictation learns it was not pasted.
    func readWaitEnded(_ write: Write) async {
        guard let waiting = takePending(write) else { return }
        let isLeft = await pasteboard.restore(.plainText(waiting.text), ifChangeCount: write.changeCount)
        await waiting.unread(isLeft)
    }
}
