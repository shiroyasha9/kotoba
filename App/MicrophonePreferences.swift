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

    /// Once per install, before the first mic choice (`MicrophoneSettings.afterFirstLaunch`): an update to a Mac with
    /// no built-in mic turns the Bluetooth switch off, as 0.4 behaved there; a new install lists its Bluetooth default.
    /// `isUpdate`: onboarding was done before (by 0.4). One device read, until the check has decided; the flag is
    /// written last, so a launch that stops halfway checks again.
    func checkFirstLaunch(isUpdate: Bool) {
        let defaults = UserDefaults.standard
        let checked = AppDefaults.Key.microphoneFirstLaunchChecked.rawValue
        let before = MicrophoneSettings(
            order: order, bluetoothOnlyWhenListed: isBluetoothOnlyWhenListed,
            isFirstLaunchChecked: defaults.bool(forKey: checked))
        guard !before.isFirstLaunchChecked else { return }
        let devices = AudioDevices.all()
        let after = before.afterFirstLaunch(
            isUpdate: isUpdate || !before.order.isEmpty, defaultInput: AudioDevices.defaultInput(), devices: devices)
        if after.order != before.order {
            entries = after.order.map { uid in Entry(uid: uid, name: devices.first { $0.uid == uid }?.name ?? uid) }
            Log.audio.notice("The first launch put the Bluetooth default in the mic list")
        }
        if after.bluetoothOnlyWhenListed != before.bluetoothOnlyWhenListed {
            isBluetoothOnlyWhenListed = after.bluetoothOnlyWhenListed
            Log.audio.notice("The update keeps the Bluetooth default of a Mac with no built-in mic")
        }
        defaults.set(after.isFirstLaunchChecked, forKey: checked)
    }

    /// The menu's quick switch: the mic moves to the top of the order (an explicit choice, so it joins it).
    func choose(uid: String, name: String) {
        let names = Dictionary(entries.map { ($0.uid, $0.name) }, uniquingKeysWith: { first, _ in first })
        entries = InputDevicePolicy.order(order, choosing: uid).map { listed in
            Entry(uid: listed, name: listed == uid ? name : names[listed] ?? listed)
        }
    }
}
