import Foundation
import Synchronization
import Testing

@testable import KotobaCore

extension FakeWorld {
    func makePipeline(readback: EditReadback) -> DictationPipeline {
        DictationPipeline(
            ports: .init(
                audio: audio, provider: provider, paster: paster, pasteboard: pasteboard, clock: clock, store: store,
                readback: readback),
            settings: .init(audioDirectory: URL(filePath: "/tmp/kotoba-tests"))
        )
    }
}

/// A readback with a fake field and a manual clock; it collects the reported edits.
final class ReadbackWorld: Sendable {
    let clock = ManualClock()
    let field = FakeFocusedField()
    let watcher: FakeFieldWatcher
    let readback: EditReadback
    private let collected = Collected()
    private let collector: Task<Void, Never>

    init(hasField: Bool = true, holdingOpen: Bool = false) {
        watcher = FakeFieldWatcher(field: hasField ? field : nil, isHeld: holdingOpen)
        let readback = EditReadback(watcher: watcher, clock: clock)
        self.readback = readback
        collector = Task { [collected] in
            for await edit in readback.edits {
                collected.edits.withLock { $0.append(edit) }
            }
        }
    }

    deinit {
        collector.cancel()
    }

    func paste(_ text: String) async {
        await readback.pasted(text)
        await readback.settle()
    }

    /// The owner's change, taken by the session.
    func type(_ text: String) async {
        field.type(text)
        await taken()
    }

    /// Focus leaves the field, and the session takes it.
    func leave() async {
        field.leave()
        await taken()
    }

    private func taken() async {
        #expect(await eventually { field.isEventTaken })
        await readback.settle()
    }

    /// The settle time passes without a change.
    func quiet() async {
        clock.advance(by: .milliseconds(500))
        await readback.settle()
    }

    /// The first edit reported, once it is collected; nil, with an issue, when none comes within `eventually`'s
    /// bound. A test that shows no edit came asserts `EditReadback.reportedEdits` once the session ended.
    func nextEdit() async -> EditReadback.Edit? {
        #expect(await eventually { !collected.edits.withLock(\.isEmpty) })
        return collected.edits.withLock(\.first)
    }
}

private final class Collected: Sendable {
    let edits = Mutex<[EditReadback.Edit]>([])
}

/// A field whose events arrive one at a time: the session asks for the next event only after it took the last one,
/// so a test knows when an event was handled without a counter in the actor.
final class FakeFocusedField: FocusedField {
    private struct State {
        var text = ""
        var reads: [Int] = []
        var isClosed = false
        var queued: [FieldEvent] = []
        var waiter: CheckedContinuation<FieldEvent?, Never>?
        var sent = 0
        /// Times the session asked for an event.
        var asked = 0
    }

    private final class Shared: Sendable {
        let state = Mutex(State())
    }

    let appBundleID: String? = "com.example.notes"
    let events: AsyncStream<FieldEvent>
    private let shared = Shared()

    init() {
        events = AsyncStream(unfolding: { [shared] in await Self.next(shared) })
    }

    /// The radius of each read.
    var reads: [Int] { shared.state.withLock(\.reads) }
    var isClosed: Bool { shared.state.withLock(\.isClosed) }
    /// The session took every event sent: it asks for the next, or it ended on it and closed the field.
    var isEventTaken: Bool { shared.state.withLock { $0.asked > $0.sent || $0.isClosed } }

    func type(_ text: String) {
        shared.state.withLock { $0.text = text }
        send(.changed)
    }

    func leave() {
        send(.left)
    }

    private func send(_ event: FieldEvent) {
        let waiter = shared.state.withLock { state -> CheckedContinuation<FieldEvent?, Never>? in
            state.sent += 1
            if let waiter = state.waiter {
                state.waiter = nil
                return waiter
            }
            state.queued.append(event)
            return nil
        }
        waiter?.resume(returning: event)
    }

    private static func next(_ shared: Shared) async -> FieldEvent? {
        await withCheckedContinuation { continuation in
            let ready = shared.state.withLock { state -> FieldEvent?? in
                state.asked += 1
                if !state.queued.isEmpty { return .some(state.queued.removeFirst()) }
                if state.isClosed { return .some(nil) }
                state.waiter = continuation
                return nil
            }
            if let ready {
                continuation.resume(returning: ready)
            }
        }
    }

    func read(radius: Int) async -> String? {
        shared.state.withLock { state in
            state.reads.append(radius)
            return state.text
        }
    }

    func close() async {
        let waiter = shared.state.withLock { state in
            state.isClosed = true
            defer { state.waiter = nil }
            return state.waiter
        }
        waiter?.resume(returning: nil)
    }
}

final class FakeFieldWatcher: FieldWatcher {
    private let field: FakeFocusedField?
    private let isHeld: Bool
    private let count = Mutex(0)
    /// Holds `focusedField()` until opened, when `isHeld`.
    let gate = Gate()

    init(field: FakeFocusedField?, isHeld: Bool) {
        self.field = field
        self.isHeld = isHeld
    }

    var opens: Int { count.withLock { $0 } }

    func focusedField() async -> (any FocusedField)? {
        count.withLock { $0 += 1 }
        if isHeld { await gate.pass() }
        return field
    }
}
