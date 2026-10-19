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

/// A warning about the mic in use, for the Microphone menu and pane (docs/spec.md, "Owner round 2026-10-16").
public enum MicrophoneWarning: Sendable, Equatable {
    /// A Bluetooth mic runs in the call profile: call-quality audio, and a slow start that can lose
    /// the first word (AirPods Pro, 2026-10-16: about 0.3 s of audio lost about 0.3 s after the
    /// start, and one stop that waited 171 ms). `interruptsPlayback` when the output is Bluetooth
    /// too: playback drops to call quality while kotoba records.
    case bluetoothMic(interruptsPlayback: Bool)
}

/// Which microphone to record from (docs/spec.md, "Audio", microphone choice).
///
/// The owner's preference order comes first: the first connected input in it is used, Bluetooth
/// included. With none of them connected, kotoba follows the system default, except that a
/// Bluetooth default is replaced by the built-in mic: a Bluetooth mic runs in the HFP call profile,
/// with low quality and a slow start that clips the first words, and opening it drops the headset's
/// playback to call quality.
public enum InputDevicePolicy {
    /// The mic to record from among the connected `devices`; nil when none is left. The mics in `leftOut` (by UID) did
    /// not open: the next in the order goes first, and the rules hold without them, so a Bluetooth default that the
    /// built-in mic replaced stays out when the built-in mic is left out.
    public static func micInUse(
        defaultInput: AudioDevice?,
        devices: [AudioDevice],
        order: [String] = [],
        leftOut: Set<String> = []
    ) -> AudioDevice? {
        let inputs = devices.filter(\.hasInput)
        let open = inputs.filter { !leftOut.contains($0.uid) }
        for uid in order {
            if let listed = open.first(where: { $0.uid == uid }) {
                return listed
            }
        }
        guard let followed = inputs.first(where: { $0.uid == defaultInput?.uid }) else { return nil }
        let chosen =
            followed.transport == .bluetooth ? inputs.first { $0.transport == .builtIn } ?? followed : followed
        return leftOut.contains(chosen.uid) ? nil : chosen
    }

    /// The order after the owner picks `uid` in the menu: it moves to the top, the rest keep their order.
    public static func order(_ order: [String], choosing uid: String) -> [String] {
        [uid] + order.filter { $0 != uid }
    }

    /// The warning for `input`, the mic kotoba records from; `outputTransport` is the system default
    /// output's transport, nil when there is none.
    public static func warning(input: AudioDevice?, outputTransport: AudioDevice.Transport?) -> MicrophoneWarning? {
        guard input?.transport == .bluetooth else { return nil }
        return .bluetoothMic(interruptsPlayback: outputTransport == .bluetooth)
    }
}
