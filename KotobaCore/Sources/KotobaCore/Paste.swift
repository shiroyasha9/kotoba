import Foundation

/// Posts Cmd-V to the focused app.
public protocol Paster: Sendable {
    func sendPaste() async throws
}

/// The general pasteboard. The pipeline writes the transcript, pastes, and restores the
/// snapshot after about 1.0 s only if `changeCount` did not move (docs/spec.md, "Paste").
public protocol Pasteboard: Sendable {
    var changeCount: Int { get async }
    /// Can be slow: reading promised data makes the owning app produce it. The pipeline takes
    /// the snapshot at key-up, concurrently with transcription (`async let`), never after it.
    func snapshot() async -> PasteboardSnapshot
    /// Writes `text` marked transient and concealed so clipboard managers skip it.
    /// Returns the change count after the write.
    func writeTransient(_ text: String) async -> Int
    func restore(_ snapshot: PasteboardSnapshot) async
}

/// Every item on the pasteboard, each as a map from type identifier to data.
public struct PasteboardSnapshot: Sendable, Equatable {
    public var items: [[String: Data]]

    public init(items: [[String: Data]]) {
        self.items = items
    }
}
