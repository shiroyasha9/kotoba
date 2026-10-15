/// An audio device as the app's CoreAudio adapter reports it.
public struct AudioDevice: Sendable, Equatable, Identifiable {
    public enum Transport: Sendable, Equatable {
        case builtIn
        /// Classic Bluetooth or Bluetooth LE. Its mic runs in the HFP call profile.
        case bluetooth
        case usb
        case other
    }

    public var id: UInt32
    /// Stable across reconnects and restarts, unlike `id`; the preference order stores it.
    public var uid: String
    public var name: String
    public var transport: Transport
    public var hasInput: Bool

    public init(id: UInt32, uid: String, name: String, transport: Transport, hasInput: Bool) {
        self.id = id
        self.uid = uid
        self.name = name
        self.transport = transport
        self.hasInput = hasInput
    }
}

/// Which microphone to record from (docs/spec.md, "Audio", microphone choice).
///
/// The owner's preference order comes first: the first connected input in it is used, Bluetooth
/// included. With none of them connected, kotoba follows the system default, except that a
/// Bluetooth default is replaced by the built-in mic: a Bluetooth mic runs in the HFP call profile,
/// with low quality and a slow start that clips the first words, and opening it drops the headset's
/// playback to call quality.
public enum InputDevicePolicy {
    /// The device to record from, or nil to follow the system default input.
    public static func preferredInput(
        defaultInput: AudioDevice?,
        devices: [AudioDevice],
        order: [String] = []
    ) -> AudioDevice? {
        let inputs = devices.filter(\.hasInput)
        for uid in order {
            if let listed = inputs.first(where: { $0.uid == uid }) {
                return listed
            }
        }
        guard let defaultInput, defaultInput.transport == .bluetooth else { return nil }
        return inputs.first { $0.transport == .builtIn }
    }

    /// The order after the owner picks `uid` in the menu: it moves to the top, the rest keep their order.
    public static func order(_ order: [String], choosing uid: String) -> [String] {
        [uid] + order.filter { $0 != uid }
    }
}
