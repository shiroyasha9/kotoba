import Testing

@testable import KotobaCore

struct ClipboardGuardTests {
    let pasteboard = FakePasteboard(text: "owner's")
    let work = PendingWork(clock: ManualClock())
    var clipboard: ClipboardGuard { ClipboardGuard(pasteboard: pasteboard, work: work) }

    /// The paste target reads the transcript; the restore it sets off has run.
    func appReads() async -> String? {
        let text = await pasteboard.appReads()
        await work.settle()
        return text
    }

    @Test func theClipboardComesBackOnceTheTranscriptIsRead() async throws {
        let clipboard = clipboard

        _ = try #require(await clipboard.writeTransient("dictated", over: await clipboard.snapshot()))
        #expect(await pasteboard.text == "dictated")
        #expect(await pasteboard.isTransient)
        #expect(await appReads() == "dictated")

        #expect(await pasteboard.text == "owner's")
    }

    @Test func aCopyBeforeTheWriteIsWhatComesBack() async throws {
        let clipboard = clipboard

        let snapshot = await clipboard.snapshot()
        await pasteboard.userCopies("copied while speaking")
        _ = try #require(await clipboard.writeTransient("dictated", over: snapshot))
        _ = await appReads()

        #expect(await pasteboard.text == "copied while speaking")
    }

    @Test func aCopyAfterTheWriteIsKept() async throws {
        let clipboard = clipboard

        let write = try #require(await clipboard.writeTransient("dictated", over: await clipboard.snapshot()))
        await pasteboard.userCopies("copied after")
        _ = await appReads()

        #expect(await clipboard.readWaitEnded(write) == false)
        #expect(await pasteboard.text == "copied after")
    }

    @Test func aSnapshotDuringAPendingRestoreIsTheOwnersClipboard() async throws {
        let clipboard = clipboard

        _ = try #require(await clipboard.writeTransient("one", over: await clipboard.snapshot()))
        _ = try #require(await clipboard.writeTransient("two", over: await clipboard.snapshot()))
        #expect(await appReads() == "two")

        #expect(await pasteboard.text == "owner's")
    }

    @Test func aCopyCancelsThePendingRestore() async throws {
        let clipboard = clipboard

        let write = try #require(await clipboard.writeTransient("dictated", over: await clipboard.snapshot()))
        await clipboard.copy("dictated")
        _ = await appReads()

        #expect(await clipboard.readWaitEnded(write) == false)
        #expect(await pasteboard.text == "dictated")
        #expect(await pasteboard.isTransient == false)
    }

    @Test func anUnreadTranscriptStaysAsAPlainCopy() async throws {
        let clipboard = clipboard

        let write = try #require(await clipboard.writeTransient("dictated", over: await clipboard.snapshot()))

        #expect(await clipboard.readWaitEnded(write))
        #expect(await pasteboard.text == "dictated")
        #expect(await pasteboard.isTransient == false)
    }

    @Test func aClipboardOverTheLimitIsNotKept() async {
        await pasteboard.holdMoreThanTheLimit()
        let clipboard = clipboard

        let write = await clipboard.writeTransient("dictated", over: await clipboard.snapshot())

        #expect(write == nil)
        #expect(await pasteboard.text == "dictated")
    }
}
