import Foundation
import Synchronization

@testable import KotobaCore

actor FakePasteboard: Pasteboard {
    private var count = 0
    /// Holds the next `changeCount` read, once, after it took its value.
    private var changeCountGate: Gate?

    var changeCount: Int {
        get async {
            // The value is read first, so a held read returns what was true before the hold.
            let value = count
            if let gate = changeCountGate {
                changeCountGate = nil
                await gate.pass()
            }
            return value
        }
    }

    func holdNextChangeCountRead(at gate: Gate) {
        changeCountGate = gate
    }

    /// The next write changes the contents at once but returns only when `gate` opens.
    private var writeReturnGate: Gate?

    func holdNextWriteReturn(at gate: Gate) {
        writeReturnGate = gate
    }
    private(set) var text: String?
    private(set) var isTransient = false
    /// How many times the full contents were read.
    private(set) var snapshots = 0

    init(text: String? = nil) {
        self.text = text
    }

    /// The clipboard holds more than `PasteboardSnapshot.byteLimit`.
    private var isOverLimit = false

    func holdMoreThanTheLimit() {
        isOverLimit = true
    }

    func snapshot() async -> PasteboardSnapshot {
        await Slowness.pause()
        snapshots += 1
        if isOverLimit { return PasteboardSnapshot(items: [], isTooLarge: true) }
        return text.map(PasteboardSnapshot.plainText) ?? PasteboardSnapshot(items: [])
    }

    /// Called at the first read of the transient text on the pasteboard now.
    private var onRead: (@Sendable () -> Void)?

    /// An app reads the clipboard (a paste target at its Cmd-V); the first read of a transient text tells its writer.
    @discardableResult
    func appReads() -> String? {
        onRead?()
        onRead = nil
        return text
    }

    func write(_ text: String) async -> Int {
        await Slowness.pause()
        return await write(text, isTransient: false, onRead: nil)
    }

    /// A clipboard manager that ignores the transient marker reads each transient text as it is written.
    private var isManagerReading = false

    func readEachWriteAsAManager() {
        isManagerReading = true
    }

    /// Runs once, at the next transient write: what the owner does between the write and the Cmd-V.
    private var onNextTransientWrite: (@Sendable () -> Void)?

    func whenWritingTransient(_ action: @escaping @Sendable () -> Void) {
        onNextTransientWrite = action
    }

    func writeTransient(_ text: String, onRead: @escaping @Sendable () -> Void) async -> Int {
        await Slowness.pause()
        let written = await write(text, isTransient: true, onRead: onRead)
        onNextTransientWrite?()
        onNextTransientWrite = nil
        if isManagerReading { appReads() }
        return written
    }

    private func write(_ text: String, isTransient transient: Bool, onRead: (@Sendable () -> Void)?) async -> Int {
        self.text = text
        isTransient = transient
        self.onRead = onRead
        count += 1
        let written = count
        if let gate = writeReturnGate {
            writeReturnGate = nil
            await gate.pass()
        }
        return written
    }

    /// The next restore waits for `gate` before it writes, as a slow pasteboard write would.
    private var restoreGate: Gate?

    func holdNextRestore(at gate: Gate) {
        restoreGate = gate
    }

    func restore(_ snapshot: PasteboardSnapshot, ifChangeCount changeCount: Int) async -> Bool {
        await Slowness.pause()
        if let gate = restoreGate {
            restoreGate = nil
            await gate.pass()
        }
        guard count == changeCount else { return false }
        text = snapshot.items.first?.first { $0.type == PasteboardSnapshot.plainTextType }
            .flatMap { String(bytes: $0.data, encoding: .utf8) }
        isTransient = false
        onRead = nil
        count += 1
        return true
    }

    /// Another app copied something.
    func userCopies(_ text: String) {
        self.text = text
        isTransient = false
        onRead = nil
        count += 1
    }
}
