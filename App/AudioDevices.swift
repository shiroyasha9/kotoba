import CoreAudio
import Foundation
import KotobaCore

/// The listeners that `AudioDevices.observe(_:)` added; they are removed when this is released.
/// `@unchecked Sendable`: `add` runs only inside `observe`, before the value is returned,
/// and read only in `deinit`.
final class AudioDeviceObservation: @unchecked Sendable {
    private var listeners: [(AudioObjectPropertyAddress, AudioObjectPropertyListenerBlock)] = []

    func add(_ address: AudioObjectPropertyAddress, _ block: @escaping AudioObjectPropertyListenerBlock) {
        listeners.append((address, block))
    }

    deinit {
        for (address, block) in listeners {
            var address = address
            AudioObjectRemovePropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &address, .main, block)
        }
    }
}

/// The CoreAudio device list, for `InputDevicePolicy`.
enum AudioDevices {
    static func all() -> [AudioDevice] {
        do {
            return try AudioHardwareSystem.shared.devices.map(device)
        } catch {
            Log.audio.error("Cannot list audio devices: \(error)")
            return []
        }
    }

    static func defaultInput() -> AudioDevice? {
        do {
            return try AudioHardwareSystem.shared.defaultInputDevice.map(device)
        } catch {
            Log.audio.error("Cannot read the default input device: \(error)")
            return nil
        }
    }

    /// The system default output's transport, for the Bluetooth mic warning
    /// (`InputDevicePolicy.warning`). Only the transport: a whole `AudioDevice` reads its streams,
    /// UID and name too (about 180 µs against 60-80 µs, review 2026-10-16).
    static func defaultOutputTransport() -> AudioDevice.Transport? {
        do {
            return try AudioHardwareSystem.shared.defaultOutputDevice.map { transport(try $0.transportType) }
        } catch {
            Log.audio.error("Cannot read the default output device: \(error)")
            return nil
        }
    }

    /// The device's nominal sample rate, or nil when it cannot be read (the device went away).
    static func nominalSampleRate(of id: AudioObjectID) -> Double? {
        try? AudioHardwareDevice(id: id).nominalSampleRate
    }

    /// The devices that can record, for the Microphone menu and Settings.
    static func inputs() -> [AudioDevice] {
        all().filter(\.hasInput)
    }

    /// The default input or output changed (the output feeds the Bluetooth mic warning), or a device
    /// connected or disconnected.
    private static let watchedProperties = [
        kAudioHardwarePropertyDefaultInputDevice, kAudioHardwarePropertyDefaultOutputDevice,
        kAudioHardwarePropertyDevices,
    ]

    /// Calls `onChange` on the main queue on each `watchedProperties` change, until the returned value
    /// is released: the app keeps one for its whole life, a window only while it is open.
    static func observe(_ onChange: @escaping @Sendable () -> Void) -> AudioDeviceObservation {
        let observation = AudioDeviceObservation()
        for selector in watchedProperties {
            var address = PropertyAddress(selector)
            let block: AudioObjectPropertyListenerBlock = { _, _ in onChange() }
            let status = AudioObjectAddPropertyListenerBlock(
                AudioObjectID(kAudioObjectSystemObject), &address, .main, block)
            if status == noErr {
                observation.add(address, block)
            } else {
                Log.audio.error("Cannot watch the audio devices (\(selector)): \(status)")
            }
        }
        return observation
    }

    /// A property that cannot be read (a device going away) counts as unknown, not as an error.
    private static func device(_ device: AudioHardwareDevice) -> AudioDevice {
        let streams = (try? device.streams) ?? []
        return AudioDevice(
            id: device.id,
            uid: (try? device.uid) ?? "",
            name: (try? device.name) ?? "",
            transport: transport((try? device.transportType) ?? 0),
            hasInput: streams.contains { (try? $0.direction) == .input }
        )
    }

    private static func transport(_ type: UInt32) -> AudioDevice.Transport {
        switch type {
        case kAudioDeviceTransportTypeBuiltIn: .builtIn
        case kAudioDeviceTransportTypeBluetooth, kAudioDeviceTransportTypeBluetoothLE: .bluetooth
        case kAudioDeviceTransportTypeUSB: .usb
        default: .other
        }
    }
}
