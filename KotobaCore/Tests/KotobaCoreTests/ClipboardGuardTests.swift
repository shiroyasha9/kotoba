import Testing

@testable import KotobaCore

struct ClipboardGuardTests {
    @Test func theClipboardFromChordDownComesBack() async {
        let pasteboard = FakePasteboard(text: "owner's")
        let clipboard = ClipboardGuard(pasteboard: pasteboard)

        let snapshot = await clipboard.snapshot()
        let write = await clipboard.writeTransient("dictated", over: snapshot)
        #expect(await pasteboard.text == "dictated")
        #expect(await pasteboard.isTransient)
        await clipboard.restore(after: write)

        #expect(await pasteboard.text == "owner's")
    }

    @Test func aCopyBeforeTheWriteIsWhatComesBack() async {
        let pasteboard = FakePasteboard(text: "owner's")
        let clipboard = ClipboardGuard(pasteboard: pasteboard)

        let snapshot = await clipboard.snapshot()
        await pasteboard.userCopies("copied while speaking")
        let write = await clipboard.writeTransient("dictated", over: snapshot)
        await clipboard.restore(after: write)

        #expect(await pasteboard.text == "copied while speaking")
    }

    @Test func aCopyAfterTheWriteIsKept() async {
        let pasteboard = FakePasteboard(text: "owner's")
        let clipboard = ClipboardGuard(pasteboard: pasteboard)

        let write = await clipboard.writeTransient("dictated", over: await clipboard.snapshot())
        await pasteboard.userCopies("copied after")
        await clipboard.restore(after: write)

        #expect(await pasteboard.text == "copied after")
    }

    @Test func aSnapshotDuringAPendingRestoreIsTheOwnersClipboard() async {
        let pasteboard = FakePasteboard(text: "owner's")
        let clipboard = ClipboardGuard(pasteboard: pasteboard)

        let first = await clipboard.writeTransient("one", over: await clipboard.snapshot())
        let second = await clipboard.writeTransient("two", over: await clipboard.snapshot())
        await clipboard.restore(after: first)
        #expect(await pasteboard.text == "two")
        await clipboard.restore(after: second)

        #expect(await pasteboard.text == "owner's")
    }

    @Test func aCopyCancelsThePendingRestore() async {
        let pasteboard = FakePasteboard(text: "owner's")
        let clipboard = ClipboardGuard(pasteboard: pasteboard)

        let write = await clipboard.writeTransient("dictated", over: await clipboard.snapshot())
        await clipboard.copy("dictated")
        await clipboard.restore(after: write)

        #expect(await pasteboard.text == "dictated")
        #expect(await pasteboard.isTransient == false)
    }

    @Test func aRestoreThatRacesTheNextWriteLeavesTheNewTranscript() async {
        let pasteboard = FakePasteboard(text: "owner's")
        let clipboard = ClipboardGuard(pasteboard: pasteboard)
        let first = await clipboard.writeTransient("A", over: await clipboard.snapshot())
        let snapshotForB = await clipboard.snapshot()

        // B's write lands, and A's restore runs before B's write call returns.
        let writeGate = Gate()
        await pasteboard.holdNextWriteReturn(at: writeGate)
        async let writingB = clipboard.writeTransient("B", over: snapshotForB)
        #expect(await eventually { await writeGate.hasWaiters })
        await clipboard.restore(after: first)
        await writeGate.open()
        _ = await writingB

        #expect(await pasteboard.text == "B")
    }
}
