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

    /// Posted in this process after each change of the order, so an open Microphone page shows a menu pick.
    static let didChange = Notification.Name("MicrophonePreferences.didChange")

    /// Empty when none is saved, or the saved order cannot be read.
    var entries: [Entry] {
        get { AppDefaults.decoded(at: .microphoneOrder, or: []) }
        set {
            AppDefaults.encode(newValue, at: .microphoneOrder)
            NotificationCenter.default.post(name: Self.didChange, object: nil)
        }
    }

    var order: [String] { entries.map(\.uid) }

    /// On (the default): a Bluetooth mic is used only when it is in the order (`InputDevicePolicy`).
    var isBluetoothOnlyWhenListed: Bool {
        get { UserDefaults.standard.bool(forKey: AppDefaults.Key.bluetoothOnlyWhenListed.rawValue) }
        set { UserDefaults.standard.set(newValue, forKey: AppDefaults.Key.bluetoothOnlyWhenListed.rawValue) }
    }

    /// Once per install, before the first mic choice: a Mac whose only mic was a Bluetooth default, used by 0.4 with an
    /// empty order, gets that mic in its order, so the switch does not stop its dictation
    /// (`InputDevicePolicy.orderAfterUpdate`). One device read, on the first launch only.
    func keepUpdatedMacsDictating() {
        let defaults = UserDefaults.standard
        let checked = AppDefaults.Key.microphoneUpdateChecked.rawValue
        guard !defaults.bool(forKey: checked) else { return }
        defaults.set(true, forKey: checked)
        let devices = AudioDevices.all()
        let updated = InputDevicePolicy.orderAfterUpdate(
            order, defaultInput: AudioDevices.defaultInput(), devices: devices)
        guard updated != order else { return }
        entries = updated.map { uid in Entry(uid: uid, name: devices.first { $0.uid == uid }?.name ?? uid) }
        Log.audio.notice("The update put the Bluetooth default in the mic list")
    }

    /// The menu's quick switch: the mic moves to the top of the order (an explicit choice, so it joins it).
    func choose(uid: String, name: String) {
        let names = Dictionary(entries.map { ($0.uid, $0.name) }, uniquingKeysWith: { first, _ in first })
        entries = InputDevicePolicy.order(order, choosing: uid).map { listed in
            Entry(uid: listed, name: listed == uid ? name : names[listed] ?? listed)
        }
    }
}
