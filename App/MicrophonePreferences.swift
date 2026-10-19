import Foundation
import KotobaCore

/// The owner's microphone preference order, saved by device UID in UserDefaults with the last
/// known name, so a disconnected mic still shows in Settings. Read on every use, so the menu,
/// Settings and the audio engine always agree.
final class MicrophonePreferences: Sendable {
    struct Entry: Codable, Equatable, Identifiable, Sendable {
        let uid: String
        var name: String

        var id: String { uid }
    }

    /// Empty when none is saved, or the saved order cannot be read.
    var entries: [Entry] {
        get { AppDefaults.decoded(at: .microphoneOrder, or: []) }
        set { AppDefaults.encode(newValue, at: .microphoneOrder) }
    }

    var order: [String] { entries.map(\.uid) }

    /// The menu's quick switch: the mic moves to the top of the order (an explicit choice, so it joins it).
    func choose(uid: String, name: String) {
        let names = Dictionary(entries.map { ($0.uid, $0.name) }, uniquingKeysWith: { first, _ in first })
        entries = InputDevicePolicy.order(order, choosing: uid).map { listed in
            Entry(uid: listed, name: listed == uid ? name : names[listed] ?? listed)
        }
    }
}
