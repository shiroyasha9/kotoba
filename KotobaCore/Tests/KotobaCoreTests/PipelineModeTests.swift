import Foundation
import Testing

@testable import KotobaCore

/// Per-app modes (story 29, docs/research/per-app-modes.md): the app in front at the stop picks the mode, the same app
/// a submit Return goes to. The mode picks the cleanup prompt, and a mode can clean every dictation. `FakeFrontApp`
/// names each process `test.app<id>`; app 100 is in front unless a test activates another.
struct PipelineModeTests {
    let world = FakeWorld(transcript: "raw words")
    let cleaner = FakeTextCleaner(result: .success("clean words"))
    /// App 200 is a writing app; app 100 and every other app use Code.
    let writingApp = ModeRules(apps: ["test.app200": .writing])

    @Test func theCleanupChordInAWritingAppCleansInWriting() async throws {
        world.frontApp.activate(200)
        let pipeline = world.makePipeline(cleaner: cleaner, modes: writingApp)

        await pipeline.cleanupTap()
        await pipeline.tap(world)
        await pipeline.settle()

        #expect(await cleaner.requests.map(\.mode) == [.writing])
        #expect(await world.paster.pasted == ["clean words"])
        #expect(try #require(await world.store.records.first).output == .cleanup(.writing))
    }

    @Test func theCleanupChordInAnAppWithNoModeCleansInTheOtherAppsMode() async {
        let pipeline = world.makePipeline(cleaner: cleaner, modes: ModeRules(otherApps: .writing))

        await pipeline.cleanupTap()
        await pipeline.tap(world)
        await pipeline.settle()

        #expect(await cleaner.requests.map(\.mode) == [.writing])
    }

    @Test func noFrontAppUsesTheOtherAppsMode() async {
        world.frontApp.activate(nil)
        let pipeline = world.makePipeline(cleaner: cleaner, modes: ModeRules(otherApps: .writing))

        await pipeline.cleanupTap()
        await pipeline.tap(world)
        await pipeline.settle()

        #expect(await cleaner.requests.map(\.mode) == [.writing])
    }

    @Test func aPlainTapInAModeThatDoesNotCleanEveryDictationPastesTheTranscript() async throws {
        world.frontApp.activate(200)
        let pipeline = world.makePipeline(cleaner: cleaner, modes: writingApp)

        await pipeline.dictate(world)

        #expect(await world.paster.pasted == ["raw words"])
        #expect(await cleaner.requests.isEmpty)
        #expect(await cleaner.warmUps == 0)
        #expect(try #require(await world.store.records.first).output == .transcript)
    }

    @Test func aModeThatCleansEveryDictationCleansAPlainTap() async throws {
        world.frontApp.activate(200)
        var modes = writingApp
        modes.cleansEveryDictation = [.writing]
        let pipeline = world.makePipeline(cleaner: cleaner, modes: modes)

        await pipeline.dictate(world)

        #expect(await cleaner.requests.map(\.mode) == [.writing])
        #expect(await world.paster.pasted == ["clean words"])
        #expect(try #require(await world.store.records.first).output == .cleanup(.writing))
    }

    @Test func theCleanerWarmsAtKeyDownInAModeThatCleansEveryDictation() async {
        world.frontApp.activate(200)
        var modes = writingApp
        modes.cleansEveryDictation = [.writing]
        let pipeline = world.makePipeline(cleaner: cleaner, modes: modes)

        await pipeline.handle(.chordDown)
        await pipeline.settle()

        #expect(await cleaner.warmUps == 1)
        await pipeline.handle(.chordUp)
        await pipeline.tap(world)
        await pipeline.settle()
        #expect(await cleaner.warmUps == 1)
    }

    @Test func theAppInFrontAtTheStopDecides() async throws {
        var modes = writingApp
        modes.cleansEveryDictation = [.writing]
        let pipeline = world.makePipeline(cleaner: cleaner, modes: modes)

        // Started in a Code app, then the owner clicked into the writing app and spoke.
        await pipeline.tap(world)
        world.frontApp.activate(200)
        await pipeline.tap(world)
        await pipeline.settle()

        #expect(await cleaner.requests.map(\.mode) == [.writing])
        #expect(try #require(await world.store.records.first).output == .cleanup(.writing))
    }

    @Test func aStopInAnAppThatDoesNotCleanEveryDictationPastesTheTranscript() async {
        world.frontApp.activate(200)
        var modes = writingApp
        modes.cleansEveryDictation = [.writing]
        let pipeline = world.makePipeline(cleaner: cleaner, modes: modes)

        await pipeline.tap(world)
        world.frontApp.activate(100)
        await pipeline.tap(world)
        await pipeline.settle()

        #expect(await world.paster.pasted == ["raw words"])
        #expect(await cleaner.requests.isEmpty)
    }

    @Test func aStopThatDecidesOnCleanupWarmsTheCleanerWhenKeyDownDidNot() async {
        var modes = writingApp
        modes.cleansEveryDictation = [.writing]
        let gate = Gate()
        let cleaner = FakeTextCleaner(result: .success("clean words"), gate: gate)
        let pipeline = world.makePipeline(cleaner: cleaner, modes: modes)

        await pipeline.tap(world)
        await pipeline.settle()
        #expect(await cleaner.warmUps == 0)
        world.frontApp.activate(200)
        await pipeline.tap(world)

        // The warm-up runs while the audio is sent, before the cleanup request.
        #expect(await eventually { await cleaner.warmUps == 1 })
        await gate.open()
        await pipeline.settle()
        #expect(await cleaner.warmUps == 1)
    }

    @Test func aRetryCleansInTheModeOfTheStopNotTheAppInFrontNow() async throws {
        world.frontApp.activate(200)
        let pipeline = world.makePipeline(cleaner: cleaner, modes: writingApp)
        await world.provider.fail(with: ProviderError.offline)

        await pipeline.cleanupTap()
        await pipeline.tap(world)
        await pipeline.settle()
        world.frontApp.activate(100)
        await world.provider.fail(with: nil)
        await pipeline.retryPending()

        #expect(await cleaner.requests.map(\.mode) == [.writing])
        #expect(try #require(await world.store.records.first).status == .recovered)
    }

    @Test func escTakesTheAppAndModeAtTheEsc() async throws {
        world.frontApp.activate(200)
        let pipeline = world.makePipeline(cleaner: cleaner, modes: writingApp)

        await pipeline.cleanupTap()
        await pipeline.handle(.escape)
        world.frontApp.activate(100)
        world.clock.advance(by: .seconds(5))
        await pipeline.settle()

        let record = try #require(await world.store.records.first)
        #expect(record.status == .cancelled)
        #expect(record.app?.bundleID == "test.app200")
        #expect(record.output == .cleanup(.writing))
    }

    @Test func aRecordingKeptAtQuitKeepsItsMode() async throws {
        world.frontApp.activate(200)
        let pipeline = world.makePipeline(cleaner: cleaner, modes: writingApp)

        await pipeline.cleanupTap()
        await pipeline.shutdown()

        let record = try #require(await world.store.records.first)
        #expect(record.status == .pending)
        #expect(record.output == .cleanup(.writing))
    }

    @Test func aFailedCleanupInAModeThatCleansEveryDictationPastesTheTranscript() async throws {
        world.frontApp.activate(200)
        var modes = writingApp
        modes.cleansEveryDictation = [.writing]
        let pipeline = world.makePipeline(
            cleaner: FakeTextCleaner(result: .failure(ProviderError.offline)), modes: modes)

        await pipeline.dictate(world)

        #expect(await world.paster.pasted == ["raw words"])
        let record = try #require(await world.store.records.first)
        #expect(await pipeline.state == .cleanupFailed(record.id))
    }

    @Test func newModesApplyToTheNextDictation() async {
        world.frontApp.activate(200)
        let pipeline = world.makePipeline(cleaner: cleaner, modes: ModeRules())

        await pipeline.updateModes(writingApp)
        await pipeline.cleanupTap()
        await pipeline.tap(world)
        await pipeline.settle()

        #expect(await cleaner.requests.map(\.mode) == [.writing])
    }

    // MARK: The pill

    @Test func theRecordingPillSaysWhenTheModeCleansEveryDictation() async {
        world.frontApp.activate(200)
        var modes = writingApp
        modes.cleansEveryDictation = [.writing]
        let pipeline = world.makePipeline(cleaner: cleaner, modes: modes)

        await pipeline.tap(world)

        #expect(await pipeline.state == .recording(isLong: false, isCleaned: true))
    }

    @Test func theRecordingPillSaysWhenTheCleanupChordStartedIt() async {
        let pipeline = world.makePipeline(cleaner: cleaner, modes: writingApp)

        await pipeline.cleanupTap()

        #expect(await pipeline.state == .recording(isLong: false, isCleaned: true))
    }

    @Test func aPlainRecordingPillSaysNothingAboutCleanup() async {
        world.frontApp.activate(200)
        let pipeline = world.makePipeline(cleaner: cleaner, modes: writingApp)

        await pipeline.tap(world)

        #expect(await pipeline.state == .recording(isLong: false))
    }

    @Test func theLongRecordingWarningKeepsTheCleanupMark() async {
        let pipeline = world.makePipeline(cleaner: cleaner, modes: writingApp)

        await pipeline.cleanupTap()
        world.clock.advance(by: .seconds(600))
        await pipeline.settle()

        #expect(await pipeline.state == .recording(isLong: true, isCleaned: true))
    }

    @Test func thePillSaysCleaningWhileTheCleanerWorks() async throws {
        let gate = Gate()
        let cleaner = FakeTextCleaner(result: .success("clean words"), gate: gate)
        let pipeline = world.makePipeline(cleaner: cleaner, modes: writingApp)

        await pipeline.cleanupTap()
        await pipeline.tap(world)
        #expect(await eventually { await gate.hasWaiters })

        #expect(await pipeline.state == .cleaning)
        await gate.open()
        await pipeline.settle()
        #expect(await pipeline.state == .idle)
    }

    @Test func aShortcutPressDuringACleanupLeavesThePillOnCleaning() async {
        let gate = Gate()
        let pipeline = world.makePipeline(
            cleaner: FakeTextCleaner(result: .success("clean words"), gate: gate), modes: writingApp)
        await pipeline.cleanupTap()
        await pipeline.tap(world)
        #expect(await eventually { await gate.hasWaiters })

        // The chord was part of another app's shortcut: the press is discarded.
        await pipeline.handle(.chordDown)
        await pipeline.handle(.chordInterrupted)
        await pipeline.handle(.chordUp)

        #expect(await pipeline.state == .cleaning)
        await gate.open()
        await pipeline.settle()
    }

    @Test func aFinalCancelDuringACleanupLeavesThePillOnCleaning() async {
        let gate = Gate()
        let pipeline = world.makePipeline(
            cleaner: FakeTextCleaner(result: .success("clean words"), gate: gate), modes: writingApp,
            cleanupDeadline: .seconds(30))
        await pipeline.cleanupTap()
        await pipeline.tap(world)
        #expect(await eventually { await gate.hasWaiters })

        await pipeline.tap(world)
        await pipeline.handle(.escape)
        world.clock.advance(by: .seconds(5))
        // Not `settle()`: it would wait for the held cleanup too.
        #expect(await eventually { await world.store.records.contains { $0.status == .cancelled } })

        #expect(await pipeline.state == .cleaning)
        await gate.open()
        await pipeline.settle()
    }

    @Test func aPlainDictationPastedDuringACleanupLeavesThePillOnCleaning() async {
        let gate = Gate()
        let pipeline = world.makePipeline(
            cleaner: FakeTextCleaner(result: .success("clean words"), gate: gate), modes: writingApp)
        await pipeline.cleanupTap()
        await pipeline.tap(world)
        #expect(await eventually { await gate.hasWaiters })

        await pipeline.tap(world)
        await pipeline.tap(world)
        #expect(await eventually { await world.paster.pasted == ["raw words"] })
        #expect(await eventually { await pipeline.state != .transcribing })

        #expect(await pipeline.state == .cleaning)
        await gate.open()
        await pipeline.settle()
        #expect(await world.paster.pasted == ["raw words", "clean words"])
    }
}

extension FakeWorld {
    /// The Undo window and the cleanup deadline are both 5 s; a test that waits out the first sets a longer second.
    func makePipeline(
        cleaner: (any TextCleaner)?, modes: ModeRules, cleanupDeadline: Duration = .seconds(5)
    ) -> DictationPipeline {
        DictationPipeline(
            ports: .init(
                audio: audio, provider: provider, paster: paster, pasteboard: pasteboard, clock: clock, store: store,
                cleaner: cleaner, frontApp: { [frontApp] in frontApp.current }),
            settings: .init(
                audioDirectory: URL(filePath: "/tmp/kotoba-tests"), noSoundWarning: .seconds(3_600),
                cleanupDeadline: cleanupDeadline, modes: modes)
        )
    }
}
