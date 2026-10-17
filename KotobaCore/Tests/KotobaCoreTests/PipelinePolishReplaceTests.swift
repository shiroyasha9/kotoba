import Foundation
import Synchronization
import Testing

@testable import KotobaCore

/// Polish where nothing can select the old text (a terminal): Backspace deletes kotoba's last paste only while nothing
/// changed since; otherwise the polished text goes to the clipboard and nothing is pasted.
struct PipelinePolishReplaceTests {
    static let spoken = PipelinePolishTests.spoken
    static let polished = PipelinePolishTests.polished

    /// A terminal: no selection, but nothing happened since kotoba's paste, so Backspace deletes exactly it.
    @Test func whereNothingCanSelectPolishDeletesThePasteByBackspace() async throws {
        let world = FakeWorld(transcript: Self.spoken)
        let input = FakeInput()
        let pipeline = world.makePipeline(
            polisher: FakePolisher(answer: Self.polished), selector: FakeSelector(), input: input)
        await pipeline.dictate(world)

        await pipeline.polishLast()

        let id = try #require(await world.store.records.first?.id)
        #expect(await world.paster.keystrokes == [.commandV, .backspaces(Self.spoken.count), .commandV])
        #expect(await world.paster.pasted == [Self.spoken, Self.polished])
        #expect(await pipeline.state == .polished(id, isReplaced: true))
    }

    @Test(arguments: [FakeInput.Change.typed, .clicked, .otherWindow, .otherApp])
    func anyChangeSinceThePasteLeavesThePolishOnTheClipboard(_ change: FakeInput.Change) async throws {
        let world = FakeWorld(transcript: Self.spoken)
        let input = FakeInput()
        let pipeline = world.makePipeline(
            polisher: FakePolisher(answer: Self.polished), selector: FakeSelector(), input: input)
        await pipeline.dictate(world)
        input.apply(change)

        await pipeline.polishLast()

        let id = try #require(await world.store.records.first?.id)
        #expect(await world.paster.keystrokes == [.commandV])
        #expect(await world.pasteboard.text == Self.polished)
        #expect(await pipeline.state == .polished(id, isReplaced: false))
        #expect(try #require(await world.store.records.first).polishedText == Self.polished)
    }

    /// The selector changed the selection and could not read it back or put it back: Backspace could delete elsewhere.
    @Test func aSelectionTheSelectorChangedLeavesThePolishOnTheClipboard() async {
        let world = FakeWorld(transcript: Self.spoken)
        let pipeline = world.makePipeline(
            polisher: FakePolisher(answer: Self.polished), selector: FakeSelector(answer: .changed), input: FakeInput())
        await pipeline.dictate(world)

        await pipeline.polishLast()

        #expect(await world.paster.keystrokes == [.commandV])
        #expect(await world.pasteboard.text == Self.polished)
    }

    /// The place is read just before the ⌘V: a window that comes to the front as the paste lands is not taken for it.
    @Test func aWindowThatComesAsThePasteLandsIsNotThePastesPlace() async {
        let world = FakeWorld(transcript: Self.spoken)
        let input = FakeInput()
        let pipeline = world.makePipeline(
            polisher: FakePolisher(answer: Self.polished), selector: FakeSelector(), input: input)
        await world.paster.whenPasting { input.apply(.otherWindow) }
        await pipeline.dictate(world)

        await pipeline.polishLast()

        #expect(await world.paster.keystrokes == [.commandV])
        #expect(await world.pasteboard.text == Self.polished)
    }

    @Test func aSubmittedDictationIsNeverDeletedByBackspace() async {
        let world = FakeWorld(transcript: "Fix the login bug, press enter")
        let pipeline = world.makePipeline(
            polisher: FakePolisher(answer: Self.polished), selector: FakeSelector(), input: FakeInput())
        await pipeline.dictate(world)

        await pipeline.polishLast()

        #expect(await world.paster.keystrokes == [.commandV, .returnKey])
        #expect(await world.pasteboard.text == Self.polished)
    }

    @Test func undoAfterABackspaceReplaceDeletesThePolishedText() async throws {
        let world = FakeWorld(transcript: Self.spoken)
        let pipeline = world.makePipeline(
            polisher: FakePolisher(answer: Self.polished), selector: FakeSelector(), input: FakeInput())
        await pipeline.dictate(world)
        await pipeline.polishLast()
        let id = try #require(await world.store.records.first?.id)

        await pipeline.undoPolish(id)

        #expect(
            await world.paster.keystrokes == [
                .commandV, .backspaces(Self.spoken.count), .commandV, .backspaces(Self.polished.count), .commandV,
            ])
        #expect(await world.paster.pasted.last == Self.spoken)
        #expect(await pipeline.state == .idle)
    }
}

/// The front window and the owner's input count, as the App's tap and window list report them.
final class FakeInput: Sendable {
    enum Change: Sendable {
        case typed
        case clicked
        case otherWindow
        case otherApp
    }

    private let mark = Mutex(InputMark(processID: 100, window: 7, inputSincePaste: 0))

    var current: InputMark { mark.withLock { $0 } }

    func apply(_ change: Change) {
        mark.withLock { mark in
            switch change {
            case .typed, .clicked: mark.inputSincePaste += 1
            case .otherWindow: mark.window += 1
            case .otherApp: mark.processID += 1
            }
        }
    }
}
