/// The owner's clipboard around a paste: a snapshot at chord-down, the transcript written as a
/// transient item, and a restore only if nothing else replaced it (docs/spec.md, "Paste").
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
    }

    private let pasteboard: any Pasteboard
    /// The latest transient write and the clipboard it replaced.
    private var pending: (write: Write, original: PasteboardSnapshot)?

    init(pasteboard: any Pasteboard) {
        self.pasteboard = pasteboard
    }

    /// Taken at chord-down, while capture starts, because reading promised data can be slow. While
    /// an earlier paste still waits to restore, the pasteboard holds that transcript, so the earlier
    /// snapshot is the owner's clipboard.
    func snapshot() async -> Snapshot {
        let changeCount = await pasteboard.changeCount
        if let pending, pending.write.changeCount == changeCount {
            return Snapshot(changeCount: changeCount, contents: pending.original)
        }
        return Snapshot(changeCount: changeCount, contents: await pasteboard.snapshot())
    }

    /// Writes the transcript as a transient item. If the owner copied something after `snapshot`,
    /// that newer clipboard is the one to restore. Nil when there is nothing to restore: the clipboard was too large
    /// to keep (`PasteboardSnapshot.isTooLarge`).
    func writeTransient(_ text: String, over snapshot: Snapshot) async -> Write? {
        let isUnchanged = await pasteboard.changeCount == snapshot.changeCount
        let original = isUnchanged ? snapshot.contents : await self.snapshot().contents
        let write = Write(changeCount: await pasteboard.write(text, isTransient: true))
        pending = original.isTooLarge ? nil : (write, original)
        return pending?.write
    }

    /// Leaves `text` on the clipboard for the owner to paste, with no restore.
    func copy(_ text: String) async {
        pending = nil
        _ = await pasteboard.write(text, isTransient: false)
    }

    /// Puts the owner's clipboard back, unless something replaced `write` since.
    func restore(after write: Write) async {
        guard let pending, pending.write == write else { return }
        self.pending = nil
        await pasteboard.restore(pending.original, ifChangeCount: write.changeCount)
    }
}
