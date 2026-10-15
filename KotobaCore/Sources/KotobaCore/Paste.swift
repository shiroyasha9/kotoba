import Foundation

/// Posts Cmd-V to the focused app.
public protocol Paster: Sendable {
    func sendPaste() async throws
}

/// The general pasteboard. The pipeline writes the transcript, pastes, and restores the
/// snapshot after about 1.0 s only if `changeCount` did not move (docs/spec.md, "Paste").
public protocol Pasteboard: Sendable {
    var changeCount: Int { get async }
    /// Can be slow: reading promised data makes the owning app produce it. `ClipboardGuard` takes
    /// the snapshot at chord-down, while capture runs, and again before the write only if the
    /// clipboard changed.
    func snapshot() async -> PasteboardSnapshot
    /// Replaces the contents with `text`. When `isTransient`, marks it transient and concealed so
    /// clipboard managers skip it. Returns the change count after the write.
    func write(_ text: String, isTransient: Bool) async -> Int
    /// Puts `snapshot` back only if the change count is still `changeCount`, checked and written in
    /// one step, so a write that lands between a check and a restore is never overwritten.
    func restore(_ snapshot: PasteboardSnapshot, ifChangeCount changeCount: Int) async
}

/// Every item on the pasteboard, each as a map from type identifier to data.
public struct PasteboardSnapshot: Sendable, Equatable {
    public var items: [[String: Data]]

    public init(items: [[String: Data]]) {
        self.items = items
    }
}
