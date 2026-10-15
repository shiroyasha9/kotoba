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

    private static let key = AppDefaults.Key.microphoneOrder.rawValue

    var entries: [Entry] {
        get {
            guard let data = UserDefaults.standard.data(forKey: Self.key) else { return [] }
            do {
                return try JSONDecoder().decode([Entry].self, from: data)
            } catch {
                Log.audio.error("Unreadable microphone order, starting empty: \(error)")
                return []
            }
        }
        set {
            do {
                UserDefaults.standard.set(try JSONEncoder().encode(newValue), forKey: Self.key)
            } catch {
                Log.audio.error("Cannot save the microphone order: \(error)")
            }
        }
    }

    var order: [String] { entries.map(\.uid) }

    /// The menu's quick switch: the mic moves to the top of the order (an explicit choice, so it joins it).
    func choose(uid: String, name: String) {
        let names = Dictionary(entries.map { ($0.uid, $0.name) }, uniquingKeysWith: { first, _ in first })
        entries = InputDevicePolicy.order(order, choosing: uid).map { listed in
            Entry(uid: listed, name: listed == uid ? name : names[listed] ?? listed)
        }
    }

    /// The mic to record from among `devices`: the first listed one, else the system default (a
    /// Bluetooth default replaced by the built-in mic, `InputDevicePolicy`).
    func preferredInput(among devices: [AudioDevice]) -> AudioDevice? {
        let defaultInput = AudioDevices.defaultInput()
        let choice = InputDevicePolicy.preferredInput(defaultInput: defaultInput, devices: devices, order: order)
        return choice ?? defaultInput
    }
}
