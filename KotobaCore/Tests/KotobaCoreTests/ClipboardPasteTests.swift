import Synchronization
import Testing

@testable import KotobaCore

/// One paste transaction through `ClipboardPaste.run(_:gate:)`: the gate, the transient write, the keys, and the
/// owner's clipboard coming back after the paste target's read.
struct ClipboardPasteTests {
    let pasteboard = FakePasteboard(text: "owner's")
    let paster: FakePaster
    let clock = ManualClock()
    let work: PendingWork
    let frontApp = FakeFrontApp()
    let input = FakeInput()
    let gate = FakePasteGate()
    let paste: ClipboardPaste

    init() {
        paster = FakePaster(pasteboard: pasteboard)
        work = PendingWork(clock: clock)
        paste = ClipboardPaste(
            pasteboard: pasteboard, paster: paster, frontApp: { [frontApp] in frontApp.current },
            place: { [input] in input.current }, readWait: .seconds(10), work: work, clock: clock)
    }

    /// Pastes `text` as Paste Again does, into the app in front now.
    @discardableResult
    func run(
        _ text: String, kind: ClipboardPaste.Kind = .again, snapshot: ClipboardPaste.PendingSnapshot? = nil
    ) async -> ClipboardPaste.Outcome {
        let request = ClipboardPaste.Request(
            id: DictationID(), text: text, kind: kind, app: frontApp.current, snapshot: snapshot)
        let outcome = await paste.run(request, gate: gate)
        await work.settle()
        return outcome
    }

    /// An app reads the transcript; the paste has heard of it.
    func appReads() async -> String? {
        let text = await pasteboard.appReads()
        await work.settle()
        return text
    }

    func advance(by duration: Duration) async {
        clock.advance(by: duration)
        await work.settle()
    }

    // MARK: - The gate

    @Test func aPasteThatMayGoWritesTheTextAndSendsTheCmdV() async throws {
        let outcome = await run("dictated")

        guard case .pasted(let pasted) = outcome else { throw FakeError() }
        #expect(pasted.isClipboardKept)
        #expect(pasted.submit == nil)
        #expect(await paster.pasted == ["dictated"])
        #expect(await paster.keystrokes == [.commandV])
    }

    /// kotoba quits, or a dictation came first: nothing pastes and the owner's clipboard stays as it was.
    @Test(arguments: [ClipboardPaste.Facts(isQuitting: true), ClipboardPaste.Facts(isOvertaken: true)])
    func aPasteThatMustNotGoLeavesEverythingAlone(facts: ClipboardPaste.Facts) async {
        await gate.answer(facts)

        #expect(await run("dictated") == .skipped)
        #expect(await paster.keystrokes.isEmpty)
        #expect(await pasteboard.text == "owner's")
    }

    /// The owner is away: a ⌘V would go to the lock screen, so the text waits on the clipboard as a plain copy.
    @Test func aPasteWhileTheOwnerIsAwayIsCopied() async {
        await gate.answer(ClipboardPaste.Facts(isPresent: false))

        #expect(await run("dictated") == .copied)
        #expect(await paster.keystrokes.isEmpty)
        #expect(await pasteboard.text == "dictated")
        #expect(await pasteboard.isTransient == false)
    }

    @Test func anotherAppInFrontGetsNoPaste() async {
        let request = ClipboardPaste.Request(id: DictationID(), text: "dictated", kind: .again, app: frontApp.current)
        frontApp.activate(200)

        #expect(await paste.run(request, gate: gate) == .copied)
        #expect(await paster.keystrokes.isEmpty)
        #expect(await pasteboard.text == "dictated")
    }

    /// With no app known when the owner asked, nothing says the app changed.
    @Test func noAppKnownPastes() async {
        let request = ClipboardPaste.Request(id: DictationID(), text: "dictated", kind: .again, app: nil)
        frontApp.activate(200)

        guard case .pasted = await paste.run(request, gate: gate) else {
            Issue.record("Not pasted")
            return
        }
        #expect(await paster.pasted == ["dictated"])
    }

    @Test func aRefusedCmdVLeavesTheTextCopiedAndReportsNothing() async {
        await paster.deny(with: FakeError())

        #expect(await run("dictated") == .copied)
        #expect(await pasteboard.text == "dictated")
        #expect(await pasteboard.isTransient == false)
        await advance(by: .seconds(10))
        #expect(gate.unread.isEmpty)
    }

    // MARK: - Keys and place

    @Test func polishDeletesTheOldTextByBackspaceRightBeforeTheCmdV() async {
        await run("polished", kind: .polish(backspaces: 3))

        #expect(await paster.keystrokes == [.backspaces(3), .commandV])
    }

    /// The place is read after the write, right before the ⌘V: a window switch during the write is where the paste
    /// went.
    @Test func thePlaceIsReadRightBeforeTheCmdV() async throws {
        await pasteboard.whenWritingTransient { [input] in input.apply(.otherWindow) }

        guard case .pasted(let pasted) = await run("dictated") else { throw FakeError() }
        #expect(pasted.place == input.current)
    }

    @Test(arguments: [true, false])
    func aDictationAskedToSubmitGetsReturnAfterTheCmdV(isSpoken: Bool) async throws {
        await gate.askSubmit(!isSpoken)

        let outcome = await run("dictated", kind: .dictation(stoppingPress: nil, submits: isSpoken))

        guard case .pasted(let pasted) = outcome else { throw FakeError() }
        #expect(pasted.submit == .sent(at: clock.now))
        #expect(await paster.keystrokes == [.commandV, .returnKey])
    }

    /// A Return in another app could run the pasted text as a command there.
    @Test func noReturnGoesToAnotherApp() async throws {
        await paster.whenPasting { [frontApp] in frontApp.activate(200) }

        let outcome = await run("dictated", kind: .dictation(stoppingPress: nil, submits: true))

        guard case .pasted(let pasted) = outcome else { throw FakeError() }
        #expect(pasted.submit == .frontAppChanged)
        #expect(await paster.keystrokes == [.commandV])
    }

    // MARK: - The restore

    /// The read is when the target asks for the text, not when it has it: the pasteboard can still be handing it over,
    /// and the target can check the clipboard again after its read (cmux drops a paste whose change count moved). A
    /// restore in that time pastes nothing (2026-10-19), so the clipboard comes back `readSettle` after the read.
    @Test func theClipboardComesBackOnlyAfterTheSettle() async {
        await run("dictated")
        #expect(await pasteboard.isTransient)
        await advance(by: ClipboardPaste.readSettle - .milliseconds(1))
        let beforeTheSettle = await pasteboard.text
        await advance(by: .milliseconds(1))

        #expect(beforeTheSettle == "dictated")
        #expect(await pasteboard.text == "owner's")
        await advance(by: .seconds(10))
        #expect(gate.unread.isEmpty)
    }

    /// A paste read and replaced by the next one before its settle passed was pasted: it is not reported, and the
    /// owner's clipboard is the one that comes back.
    @Test func aPasteReplacedDuringItsSettleIsNotReported() async {
        await run("A")
        await run("B")
        await advance(by: ClipboardPaste.readSettle)

        #expect(gate.unread.isEmpty)
        #expect(await pasteboard.text == "owner's")
    }

    @Test func aCopyBeforeTheWriteIsWhatComesBack() async {
        let snapshot = paste.snapshot()
        _ = await snapshot.value
        await pasteboard.userCopies("copied while speaking")
        await run("dictated", snapshot: snapshot)
        await advance(by: ClipboardPaste.readSettle)

        #expect(await pasteboard.text == "copied while speaking")
    }

    @Test func aCopyAfterTheWriteIsKeptAndThePasteCountsAsUnread() async {
        await paster.readLater()
        await run("dictated")
        await pasteboard.userCopies("copied after")
        _ = await appReads()
        await advance(by: .seconds(10))

        #expect(await pasteboard.text == "copied after")
        #expect(gate.unread == [false])
    }

    @Test func aSnapshotDuringAPendingRestoreIsTheOwnersClipboard() async {
        await paster.readLater()
        await run("one")
        await run("two")
        #expect(await appReads() == "two")
        await advance(by: ClipboardPaste.readSettle)

        #expect(await pasteboard.text == "owner's")
    }

    @Test func aCopyCancelsThePendingRestore() async {
        await paster.readLater()
        await run("dictated")
        await paste.copy("dictated")
        _ = await appReads()
        await advance(by: .seconds(10))

        #expect(await pasteboard.text == "dictated")
        #expect(await pasteboard.isTransient == false)
        #expect(gate.unread.isEmpty)
    }

    /// A read before the Cmd-V went out is a clipboard manager's, not the paste target's: nothing comes back at
    /// once. That read took the signal, so the clipboard comes back 1 s after the Cmd-V, and the paste is not taken
    /// for unread.
    @Test func aReadBeforeTheCmdVRestoresOneSecondAfterIt() async {
        await pasteboard.readEachWriteAsAManager()
        await run("dictated")
        await advance(by: .milliseconds(999))
        let beforeTheSecond = await pasteboard.text
        await advance(by: .milliseconds(1))

        #expect(beforeTheSecond == "dictated")
        #expect(await pasteboard.text == "owner's")
        await advance(by: .seconds(10))
        #expect(gate.unread.isEmpty)
    }

    /// An app reads the text while its write is still on its way: the same 1 s rule.
    @Test func aReadWhileTheWriteIsOnItsWayRestoresOneSecondAfterTheCmdV() async {
        let writing = Gate()
        await pasteboard.holdNextWriteReturn(at: writing)
        await paster.readLater()

        async let outcome = paste.run(
            ClipboardPaste.Request(id: DictationID(), text: "dictated", kind: .again, app: nil), gate: gate)
        #expect(await eventually { await writing.hasWaiters })
        _ = await appReads()
        await writing.open()
        _ = await outcome
        await advance(by: .seconds(1))

        #expect(await pasteboard.text == "owner's")
        #expect(gate.unread.isEmpty)
    }

    /// A read early, then B within the 1 s: A was probably pasted, so it is not reported unread.
    @Test func aPasteReadEarlyAndReplacedIsNotReported() async {
        await pasteboard.readEachWriteAsAManager()
        await paster.readLater()
        await run("A")
        await run("B")

        #expect(gate.unread.isEmpty)
    }

    /// A pasted and unread, then B replaces it: A learns it was not pasted (not left on the clipboard).
    @Test func anUnreadPasteReplacedByTheNextIsReported() async {
        await paster.readLater()
        await run("A")
        await run("B")

        #expect(gate.unread == [false])
        #expect(await appReads() == "B")
        await advance(by: ClipboardPaste.readSettle)
        #expect(await pasteboard.text == "owner's")
    }

    @Test func anUnreadTranscriptStaysAsAPlainCopy() async {
        await paster.readLater()
        await run("dictated")
        await advance(by: .seconds(10))

        #expect(await pasteboard.text == "dictated")
        #expect(await pasteboard.isTransient == false)
        #expect(gate.unread == [true])
    }

    /// Too large to keep: the read still ends the wait (no restore, nothing to report), and a paste no app read is
    /// still reported.
    @Test func aClipboardOverTheLimitIsNotKeptButTheReadIsWaitedFor() async throws {
        await pasteboard.holdMoreThanTheLimit()

        guard case .pasted(let first) = await run("dictated") else { throw FakeError() }
        await advance(by: ClipboardPaste.readSettle)
        #expect(first.isClipboardKept == false)
        #expect(await pasteboard.text == "dictated")
        await paster.readLater()
        await run("second")
        await advance(by: .seconds(10))

        #expect(await pasteboard.text == "second")
        #expect(gate.unread == [true])
    }
}

/// The pipeline's side of a paste: what it answers, and what it heard.
actor FakePasteGate: PasteGate {
    private var facts = ClipboardPaste.Facts()
    private var isAsked = false
    private let reports = Mutex<[Bool]>([])

    /// Whether each paste no app read was left on the clipboard, in order.
    nonisolated var unread: [Bool] { reports.withLock { $0 } }

    func answer(_ facts: ClipboardPaste.Facts) {
        self.facts = facts
    }

    func askSubmit(_ isAsked: Bool) {
        self.isAsked = isAsked
    }

    func facts(for request: ClipboardPaste.Request) -> ClipboardPaste.Facts {
        facts
    }

    func isSubmitAsked(_ request: ClipboardPaste.Request) -> Bool {
        isAsked
    }

    func pasteWentUnread(_ request: ClipboardPaste.Request, isLeftOnClipboard: Bool) {
        reports.withLock { $0.append(isLeftOnClipboard) }
    }
}
