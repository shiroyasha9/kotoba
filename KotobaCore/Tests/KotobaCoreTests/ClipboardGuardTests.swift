import Synchronization
import Testing

@testable import KotobaCore

struct ClipboardGuardTests {
    let pasteboard = FakePasteboard(text: "owner's")
    let work = PendingWork(clock: ManualClock())
    let clipboard: ClipboardGuard
    /// What each dictation learned about its unread paste, in order: true when left on the clipboard.
    let unread = UnreadReports()

    init() {
        clipboard = ClipboardGuard(pasteboard: pasteboard, work: work)
    }

    /// Writes `text` and sends its Cmd-V.
    func paste(_ text: String) async throws -> ClipboardGuard.Write {
        let write = try #require(await write(text))
        await clipboard.willPaste(write, readBy: .now + .seconds(10))
        return write
    }

    func write(_ text: String) async -> ClipboardGuard.Write? {
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
        let write = try #require(await clipboard.writeTransient("dictated", over: snapshot) { _ in })
        await clipboard.willPaste(write, readBy: .now + .seconds(10))
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

    /// A read before the Cmd-V went out is a clipboard manager's, not the paste target's: nothing comes back early.
    @Test func aReadBeforeTheCmdVIsNotThePasteTargets() async throws {
        let write = try #require(await write("dictated"))
        _ = await appReads()
        await clipboard.willPaste(write, readBy: .now + .seconds(10))
        _ = await appReads()

        #expect(await pasteboard.text == "dictated")
        await clipboard.readWaitEnded(write)
        #expect(await pasteboard.text == "dictated")
        #expect(unread.list == [true])
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

    @Test func aClipboardOverTheLimitIsNotKept() async {
        await pasteboard.holdMoreThanTheLimit()

        let write = await write("dictated")

        #expect(write == nil)
        #expect(await pasteboard.text == "dictated")
    }
}

final class UnreadReports: Sendable {
    private let reports = Mutex<[Bool]>([])

    var list: [Bool] { reports.withLock { $0 } }

    func add(_ isLeftOnClipboard: Bool) {
        reports.withLock { $0.append(isLeftOnClipboard) }
    }
}
