import Foundation

/// Posts Cmd-V, and Return for a submit phrase, to the focused app.
public protocol Paster: Sendable {
    func sendPaste() async throws
    /// Return with no modifiers, posted right after a Cmd-V into the same event stream, so the app gets it after
    /// the paste.
    func sendReturn() async throws
    /// Backspace `count` times with no modifiers, before a Cmd-V in the same event stream: Polish deletes the text
    /// kotoba pasted where it cannot select it (a terminal).
    func sendBackspaces(_ count: Int) async throws
}

/// The general pasteboard. The pipeline writes the transcript, pastes, and restores the snapshot once the paste target
/// read the transcript, only if `changeCount` did not move (docs/spec.md, "Paste").
public protocol Pasteboard: Sendable {
    var changeCount: Int { get async }
    /// Can be slow: reading promised data makes the owning app produce it. `ClipboardPaste` takes
    /// the snapshot at the announcement, while capture runs, and again before the write only if the
    /// clipboard changed.
    func snapshot() async -> PasteboardSnapshot
    /// Replaces the contents with `text`, for the owner to paste. Returns the change count after the write.
    func write(_ text: String) async -> Int
    /// Replaces the contents with `text` for a paste, marked transient and concealed so clipboard managers skip it.
    /// The text is handed over only when an app reads it, so `onRead` runs once, at the first read: the paste
    /// target's, at its Cmd-V. A text replaced before any read never calls it. Returns the change count after the
    /// write.
    func writeTransient(_ text: String, onRead: @escaping @Sendable () -> Void) async -> Int
    /// Puts `snapshot` back only if the change count is still `changeCount`, and returns whether it did. The check
    /// and the write are one call, so a write by kotoba between them cannot happen; another app's copy in that
    /// instant can still be overwritten.
    @discardableResult
    func restore(_ snapshot: PasteboardSnapshot, ifChangeCount changeCount: Int) async -> Bool
}

/// Every item on the pasteboard, each as its types and their data in the item's order: an app that pastes takes the
/// first type it reads, so rich text written back in another order can paste as plain text.
public struct PasteboardSnapshot: Sendable, Equatable {
    /// One type of an item and its data.
    public struct Representation: Sendable, Equatable {
        public var type: String
        public var data: Data

        public init(type: String, data: Data) {
            self.type = type
            self.data = data
        }
    }

    /// The most a snapshot holds in memory (lead, 2026-10-17). A larger clipboard (a big image, a long spreadsheet
    /// range) is not kept: the dictation still pastes, and the earlier clipboard is gone.
    public static let byteLimit = 64 * 1024 * 1024

    public var items: [[Representation]]
    /// The clipboard held more than `byteLimit`; `items` is empty and nothing is restored.
    public var isTooLarge: Bool

    public init(items: [[Representation]], isTooLarge: Bool = false) {
        self.items = items
        self.isTooLarge = isTooLarge
    }

    /// The plain text type (`NSPasteboard.PasteboardType.string`).
    public static let plainTextType = "public.utf8-plain-text"

    /// One item with `text` as plain text.
    public static func plainText(_ text: String) -> Self {
        Self(items: [[Representation(type: plainTextType, data: Data(text.utf8))]])
    }
}
