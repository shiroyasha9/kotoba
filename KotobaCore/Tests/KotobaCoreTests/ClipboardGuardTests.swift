import Synchronization
import Testing

@testable import KotobaCore

struct ClipboardGuardTests {
    let pasteboard = FakePasteboard(text: "owner's")
    let clock = ManualClock()
    let work: PendingWork
    let clipboard: ClipboardGuard
    /// What each dictation learned about its unread paste, in order: true when left on the clipboard.
    let unread = UnreadReports()

    init() {
        work = PendingWork(clock: clock)
        clipboard = ClipboardGuard(pasteboard: pasteboard, work: work, clock: clock)
    }

    /// Writes `text` and sends its Cmd-V.
    func paste(_ text: String) async throws -> ClipboardGuard.Write {
        let write = await write(text)
        await clipboard.willPaste(write, readBy: clock.now + .seconds(10))
        return write
    }

    func write(_ text: String) async -> ClipboardGuard.Write {
        await clipboard.writeTransient(text, over: await clipboard.snapshot()) { [unread] isLeft in
            unread.add(isLeft)
        }
    }

    /// The paste target reads the transcript; the restore it sets off has run.
    func appReads() async -> String? {
        let text = await pasteboard.appReads()
        await work.settle()
        return text
    }

    @Test func theClipboardComesBackOnceTheTranscriptIsRead() async throws {
        _ = try await paste("dictated")
        #expect(await pasteboard.text == "dictated")
        #expect(await pasteboard.isTransient)
        #expect(await appReads() == "dictated")

        #expect(await pasteboard.text == "owner's")
    }

    @Test func aCopyBeforeTheWriteIsWhatComesBack() async throws {
        let snapshot = await clipboard.snapshot()
        await pasteboard.userCopies("copied while speaking")
        let write = await clipboard.writeTransient("dictated", over: snapshot) { _ in }
        await clipboard.willPaste(write, readBy: clock.now + .seconds(10))
        _ = await appReads()

        #expect(await pasteboard.text == "copied while speaking")
    }

    @Test func aCopyAfterTheWriteIsKeptAndThePasteCountsAsUnread() async throws {
        let write = try await paste("dictated")
        await pasteboard.userCopies("copied after")
        _ = await appReads()
        await clipboard.readWaitEnded(write)

        #expect(await pasteboard.text == "copied after")
        #expect(unread.list == [false])
    }

    @Test func aSnapshotDuringAPendingRestoreIsTheOwnersClipboard() async throws {
        _ = try await paste("one")
        _ = try await paste("two")
        #expect(await appReads() == "two")

        #expect(await pasteboard.text == "owner's")
    }

    @Test func aCopyCancelsThePendingRestore() async throws {
        let write = try await paste("dictated")
        await clipboard.copy("dictated")
        _ = await appReads()
        await clipboard.readWaitEnded(write)

        #expect(await pasteboard.text == "dictated")
        #expect(await pasteboard.isTransient == false)
        #expect(unread.list.isEmpty)
    }

    /// A read before the Cmd-V went out is a clipboard manager's, not the paste target's: nothing comes back at
    /// once. That read took the signal, so the clipboard comes back 1 s after the Cmd-V, and the paste is not taken
    /// for unread.
    @Test func aReadBeforeTheCmdVRestoresOneSecondAfterIt() async throws {
        let write = await write("dictated")
        _ = await appReads()
        await clipboard.willPaste(write, readBy: clock.now + .seconds(10))
        _ = await appReads()
        clock.advance(by: .milliseconds(999))
        await work.settle()
        let beforeTheSecond = await pasteboard.text
        clock.advance(by: .milliseconds(1))
        await work.settle()

        #expect(beforeTheSecond == "dictated")
        #expect(await pasteboard.text == "owner's")
        clock.advance(by: .seconds(10))
        await work.settle()
        #expect(unread.list.isEmpty)
    }

    /// The early read's report reaches the guard after the Cmd-V went out: the same 1 s rule.
    @Test func anEarlyReadReportedAfterTheCmdVRestoresOneSecondAfter() async throws {
        let write = await write("dictated")
        await pasteboard.appReads()
        await clipboard.willPaste(write, readBy: clock.now + .seconds(10))
        await work.settle()
        clock.advance(by: .seconds(1))
        await work.settle()

        #expect(await pasteboard.text == "owner's")
        #expect(unread.list.isEmpty)
    }

    /// A read early, then B within the 1 s: A was probably pasted, so it is not reported unread.
    @Test func aPasteReadEarlyAndReplacedIsNotReported() async throws {
        let write = await write("A")
        _ = await appReads()
        await clipboard.willPaste(write, readBy: clock.now + .seconds(10))
        _ = try await paste("B")
        await work.settle()

        #expect(unread.list.isEmpty)
    }

    /// A pasted and unread, then B replaces it: A learns it was not pasted (not left on the clipboard).
    @Test func anUnreadPasteReplacedByTheNextIsReported() async throws {
        _ = try await paste("A")
        _ = try await paste("B")
        await work.settle()

        #expect(unread.list == [false])
        #expect(await appReads() == "B")
        #expect(await pasteboard.text == "owner's")
    }

    /// A write whose Cmd-V never went out (paste not allowed) is not a paste: nothing to report.
    @Test func aWriteWithNoCmdVReplacedIsNotReported() async throws {
        _ = await write("A")
        _ = try await paste("B")
        await work.settle()

        #expect(unread.list.isEmpty)
    }

    @Test func anUnreadTranscriptStaysAsAPlainCopy() async throws {
        let write = try await paste("dictated")

        await clipboard.readWaitEnded(write)

        #expect(await pasteboard.text == "dictated")
        #expect(await pasteboard.isTransient == false)
        #expect(unread.list == [true])
    }

    /// Too large to keep: the read still ends the wait (no restore, nothing to report), and a paste no app read is
    /// still reported.
    @Test func aClipboardOverTheLimitIsNotKeptButTheReadIsWaitedFor() async throws {
        await pasteboard.holdMoreThanTheLimit()

        let first = try await paste("dictated")
        #expect(first.isClipboardKept == false)
        #expect(await appReads() == "dictated")
        #expect(await pasteboard.text == "dictated")
        let unreadOne = try await paste("second")
        await clipboard.readWaitEnded(unreadOne)

        #expect(await pasteboard.text == "second")
        #expect(unread.list == [true])
    }
}

final class UnreadReports: Sendable {
    private let reports = Mutex<[Bool]>([])

    var list: [Bool] { reports.withLock { $0 } }

    func add(_ isLeftOnClipboard: Bool) {
        reports.withLock { $0.append(isLeftOnClipboard) }
    }
}
