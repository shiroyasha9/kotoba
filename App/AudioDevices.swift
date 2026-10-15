import CoreAudio
import Foundation
import KotobaCore

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

    /// The system default output, for the Bluetooth mic warning (`InputDevicePolicy.warning`).
    static func defaultOutput() -> AudioDevice? {
        do {
            return try AudioHardwareSystem.shared.defaultOutputDevice.map(device)
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

    /// Calls `onChange` on the main queue when the default input or output changes (the output feeds
    /// the Bluetooth mic warning) or a device connects or disconnects. Lives as long as the app.
    static func observeChanges(_ onChange: @escaping @Sendable () -> Void) {
        let selectors = [
            kAudioHardwarePropertyDefaultInputDevice, kAudioHardwarePropertyDefaultOutputDevice,
            kAudioHardwarePropertyDevices,
        ]
        for selector in selectors {
            var address = PropertyAddress(selector)
            AudioObjectAddPropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &address, .main) { _, _ in
                onChange()
            }
        }
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
