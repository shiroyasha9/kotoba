import Foundation
import Synchronization
import Testing

@testable import KotobaCore

/// Submit after paste: a transcript that ends with a submit phrase is pasted without it, then Return goes out.
/// Paste Last and Copy Last send a stored text again.
struct PipelineSubmitTests {
    @Test func theTextIsPastedWithoutThePhraseThenReturn() async throws {
        let world = FakeWorld(transcript: "Fix the login bug. Press enter.")
        let pipeline = world.makePipeline()

        await pipeline.dictate(world)

        #expect(await world.paster.pasted == ["Fix the login bug."])
        #expect(await world.paster.keystrokes == [.commandV, .returnKey])
        #expect(try #require(await world.store.records.first).transcript == "Fix the login bug.")
    }

    @Test func noPhraseSendsNoReturn() async {
        let world = FakeWorld(transcript: "Fix the login bug.")
        let pipeline = world.makePipeline()

        await pipeline.dictate(world)

        #expect(await world.paster.keystrokes == [.commandV])
    }

    @Test func turnedOffPastesThePhraseAsText() async {
        let world = FakeWorld(transcript: "Fix the login bug. Press enter.")
        let pipeline = world.makePipeline()
        await pipeline.updateSubmitPhrase(isOn: false)

        await pipeline.dictate(world)

        #expect(await world.paster.pasted == ["Fix the login bug. Press enter."])
        #expect(await world.paster.keystrokes == [.commandV])
    }

    @Test func returnHasItsLatencyMarkAfterThePaste() async throws {
        let world = FakeWorld(transcript: "Run it. Press enter.")
        let pipeline = world.makePipeline()

        await pipeline.dictate(world)

        let latency = try #require(await world.store.records.first).latency
        let pasteSent = try #require(latency.offsets[.pasteSent])
        #expect(try #require(latency.offsets[.returnSent]) >= pasteSent)
    }

    @Test func theCleanerNeverSeesThePhrase() async throws {
        let world = FakeWorld(transcript: "um fix the bug. Press enter.")
        let cleaner = FakeTextCleaner(result: .success("Fix the bug."))
        let pipeline = world.makePipeline(cleaner: cleaner)

        await pipeline.cleanupTap()
        await pipeline.tap(world)
        await pipeline.settle()

        #expect(await cleaner.requests.map(\.transcript) == ["um fix the bug."])
        #expect(await world.paster.pasted == ["Fix the bug."])
        #expect(await world.paster.keystrokes == [.commandV, .returnKey])
    }

    @Test func aFailedCleanupPastesTheRawTextThenReturn() async {
        let world = FakeWorld(transcript: "fix the bug. Press return.")
        let pipeline = world.makePipeline(cleaner: FakeTextCleaner(result: .failure(FakeError())))

        await pipeline.cleanupTap()
        await pipeline.tap(world)
        await pipeline.settle()

        #expect(await world.paster.pasted == ["fix the bug."])
        #expect(await world.paster.keystrokes == [.commandV, .returnKey])
    }

    /// The phrase is matched on what the owner said, before the replacements: a rule cannot make or break it.
    @Test func replacementsRunAfterThePhraseIsRemoved() async {
        let dictionary = PersonalDictionary(rules: [
            ReplacementRule(find: "enter", replacement: "Enter key"),
            ReplacementRule(find: "hit enter", replacement: "press enter"),
        ])
        let world = FakeWorld(transcript: "Press enter on the form. Press enter.")
        let pipeline = world.makePipeline(cleaner: nil, dictionary: dictionary)
        await pipeline.dictate(world)

        let rewritten = FakeWorld(transcript: "Looks good. Hit enter.")
        let second = rewritten.makePipeline(cleaner: nil, dictionary: dictionary)
        await second.dictate(rewritten)

        #expect(await world.paster.pasted == ["Press Enter key on the form."])
        #expect(await world.paster.keystrokes == [.commandV, .returnKey])
        #expect(await rewritten.paster.pasted == ["Looks good. press enter."])
        #expect(await rewritten.paster.keystrokes == [.commandV])
    }

    /// Return submits the field, so there is no pasted text left to follow for edits.
    @Test func aSubmittedPasteStartsNoReadback() async {
        let world = FakeWorld(transcript: "deploy it to versel today. Press enter.")
        let readback = ReadbackWorld()
        let pipeline = world.makePipeline(readback: readback.readback)

        await pipeline.dictate(world)
        await readback.readback.settle()

        #expect(await world.paster.keystrokes == [.commandV, .returnKey])
        #expect(readback.watcher.opens == 0)
    }

    @Test func aCopiedTranscriptSendsNoReturn() async {
        let world = FakeWorld(transcript: "Fix it. Press enter.")
        await world.paster.deny(with: FakeError())
        let pipeline = world.makePipeline()

        await pipeline.dictate(world)

        #expect(await world.pasteboard.text == "Fix it.")
        #expect(await world.paster.keystrokes.isEmpty)
    }

    @Test func aRetryRemovesThePhraseAndSendsNoReturn() async throws {
        let world = FakeWorld(transcript: "Fix it. Press enter.")
        let pipeline = world.makePipeline()
        await world.provider.fail(with: ProviderError.offline)
        await pipeline.dictate(world)

        await world.provider.fail(with: nil)
        await pipeline.retryPending()

        let record = try #require(await world.store.records.first)
        #expect(record.status == .recovered)
        #expect(record.transcript == "Fix it.")
        #expect(await world.paster.keystrokes.isEmpty)
    }

    // MARK: Return stop gesture

    @Test func returnWhileRecordingStopsThenSubmitsAfterThePaste() async throws {
        let world = FakeWorld(transcript: "Fix the login bug.")
        let pipeline = world.makePipeline()

        await pipeline.tap(world)
        world.clock.advance(by: .seconds(3))
        await pipeline.handle(.submit)
        await pipeline.settle()

        #expect(await world.paster.pasted == ["Fix the login bug."])
        #expect(await world.paster.keystrokes == [.commandV, .returnKey])
        let latency = try #require(await world.store.records.first).latency
        #expect(latency.offsets[.stop] == .seconds(3))
    }

    /// End to end: the Return key, classified as the tap does while recording, stops and submits once.
    @Test func theReturnKeyFromTheClassifierStopsAndSubmits() async {
        let world = FakeWorld(transcript: "Fix the login bug.")
        let pipeline = world.makePipeline()
        var classifier = HotkeyClassifier(cleanupChord: nil, isReturnGestureOn: true)

        await pipeline.tap(world)
        classifier.isRecordingShown = true
        var decisions = [classifier.classify(.keyDown(keyCode: KeyCode.return, modifiers: [], isRepeat: false))]
        classifier.isRecordingShown = false
        decisions.append(classifier.classify(.keyDown(keyCode: KeyCode.return, modifiers: [], isRepeat: true)))
        decisions.append(classifier.classify(.keyUp(keyCode: KeyCode.return, modifiers: [])))
        for decision in decisions {
            for event in decision.events {
                await pipeline.handle(event)
            }
        }
        await pipeline.settle()

        #expect(decisions.allSatisfy { $0.isSwallowed })
        #expect(await world.paster.pasted == ["Fix the login bug."])
        #expect(await world.paster.keystrokes == [.commandV, .returnKey])
    }

    @Test func returnAndAPhraseSendOneReturn() async {
        let world = FakeWorld(transcript: "Fix the login bug. Press enter.")
        let pipeline = world.makePipeline()

        await pipeline.tap(world)
        await pipeline.handle(.submit)
        await pipeline.settle()

        #expect(await world.paster.pasted == ["Fix the login bug."])
        #expect(await world.paster.keystrokes == [.commandV, .returnKey])
    }

    @Test func returnWorksWithThePhraseSettingOff() async {
        let world = FakeWorld(transcript: "Fix the login bug.")
        let pipeline = world.makePipeline()
        await pipeline.updateSubmitPhrase(isOn: false)

        await pipeline.tap(world)
        await pipeline.handle(.submit)
        await pipeline.settle()

        #expect(await world.paster.keystrokes == [.commandV, .returnKey])
    }

    @Test func returnWithNoRecordingDoesNothing() async {
        let world = FakeWorld(transcript: "Fix the login bug.")
        let pipeline = world.makePipeline()

        await pipeline.handle(.submit)
        await pipeline.settle()

        #expect(await pipeline.state == .idle)
        #expect(await world.store.records.isEmpty)
        #expect(await world.paster.keystrokes.isEmpty)
    }

    @Test func aFailedTranscriptionAfterReturnSendsNothing() async {
        let world = FakeWorld(transcript: "Fix the login bug.")
        await world.provider.fail(with: ProviderError.offline)
        let pipeline = world.makePipeline()

        await pipeline.tap(world)
        await pipeline.handle(.submit)
        await pipeline.settle()
        await world.provider.fail(with: nil)
        await pipeline.retryPending()

        #expect(await world.paster.keystrokes.isEmpty)
    }

    /// The tap still swallowed a Return pressed just after the stop, before the indicator left recording.
    @Test func returnJustAfterTheStopSubmitsThatDictation() async {
        let world = FakeWorld(transcript: "Fix the login bug.")
        let gate = Gate()
        await world.provider.hold(at: gate)
        let pipeline = world.makePipeline()

        await pipeline.tap(world)
        await pipeline.tap(world)
        await pipeline.handle(.submit)
        #expect(await eventually { await gate.hasWaiters })
        await gate.open()
        await pipeline.settle()

        #expect(await world.paster.keystrokes == [.commandV, .returnKey])
    }

    @Test func returnAfterTheDictationEndedDoesNothing() async {
        let world = FakeWorld(transcript: "Fix the login bug.")
        let pipeline = world.makePipeline()

        await pipeline.dictate(world)
        await pipeline.handle(.submit)
        await pipeline.settle()
        await pipeline.dictate(world)

        #expect(await world.paster.keystrokes == [.commandV, .commandV])
    }

    // MARK: Front app at stop

    /// The owner went to another app while the text was on its way: it is never pasted (or submitted) there; it
    /// stays on the clipboard and the pill says so.
    @Test(arguments: ["Fix the login bug. Press enter.", "Fix the login bug."])
    func anotherFrontAppAtPasteGetsNothingAndTheTextIsCopied(transcript: String) async throws {
        let world = FakeWorld(transcript: transcript)
        let gate = Gate()
        await world.provider.hold(at: gate)
        let pipeline = world.makePipeline()

        await pipeline.tap(world)
        await pipeline.tap(world)
        world.frontApp.activate(200)
        #expect(await eventually { await gate.hasWaiters })
        await gate.open()
        await pipeline.settle()
        world.clock.advance(by: .seconds(30))
        await pipeline.settle()

        #expect(await world.paster.keystrokes == [])
        #expect(await world.pasteboard.text == "Fix the login bug.")
        #expect(await world.pasteboard.isTransient == false)
        let record = try #require(await world.store.records.first)
        #expect(record.status == .copied)
        #expect(await pipeline.state == .copied(record.id))
    }

    /// With no front app known at the stop there is nothing to compare: the text pastes.
    @Test func anUnknownFrontAppAtTheStopStillPastes() async {
        let world = FakeWorld(transcript: "Fix the login bug.")
        world.frontApp.activate(nil)
        let pipeline = world.makePipeline()
        let gate = Gate()
        await world.provider.hold(at: gate)

        await pipeline.tap(world)
        await pipeline.tap(world)
        world.frontApp.activate(200)
        #expect(await eventually { await gate.hasWaiters })
        await gate.open()
        await pipeline.settle()

        #expect(await world.paster.pasted == ["Fix the login bug."])
    }

    @Test func theSameFrontAppAtPasteGetsTheReturn() async {
        let world = FakeWorld(transcript: "Fix the login bug. Press enter.")
        let gate = Gate()
        await world.provider.hold(at: gate)
        let pipeline = world.makePipeline()

        await pipeline.tap(world)
        await pipeline.tap(world)
        world.frontApp.activate(200)
        world.frontApp.activate(100)
        #expect(await eventually { await gate.hasWaiters })
        await gate.open()
        await pipeline.settle()

        #expect(await world.paster.keystrokes == [.commandV, .returnKey])
    }
}

/// The front app's process id; a test changes it to switch apps.
final class FakeFrontApp: Sendable {
    private let value = Mutex<Int32?>(100)

    var id: Int32? { value.withLock { $0 } }

    /// The front app as the pipeline reads it; each process id is its own app, `test.app<id>`.
    var current: FrontApp? {
        id.map { FrontApp(processID: $0, app: DictationApp(bundleID: "test.app\($0)", name: "App \($0)")) }
    }

    func activate(_ id: Int32?) {
        value.withLock { $0 = id }
    }
}
