import CoreAudio
import Foundation
import KotobaCore
import Synchronization

/// The listeners that `AudioDevices.observe(_:)` added; they are removed when this is released. A restart of the audio
/// service (coreaudiod) drops every listener a client added (AudioHardware.h, `kAudioHardwarePropertyServiceRestarted`),
/// so the observation adds its own again before it reports the restart.
final class AudioDeviceObservation: Sendable {
    /// `AudioObjectPropertyListenerBlock` is not marked Sendable; CoreAudio calls each block on the main queue.
    private struct Listener: @unchecked Sendable {
        let address: AudioObjectPropertyAddress
        let block: AudioObjectPropertyListenerBlock
    }

    private let onChange: @Sendable (AudioDevices.Change) -> Void
    /// Changed on the main queue at a restart, and by `init` and `deinit` on the owner's thread.
    private let listeners = Mutex<[Listener]>([])

    init(_ onChange: @escaping @Sendable (AudioDevices.Change) -> Void) {
        self.onChange = onChange
        addListeners()
    }

    deinit {
        removeListeners()
    }

    private func addListeners() {
        for (selector, change) in AudioDevices.watchedProperties {
            var address = PropertyAddress(selector)
            let block: AudioObjectPropertyListenerBlock = { [weak self] _, _ in self?.changed(change) }
            let status = AudioObjectAddPropertyListenerBlock(
                AudioObjectID(kAudioObjectSystemObject), &address, .main, block)
            if status == noErr {
                let listener = Listener(address: address, block: block)
                listeners.withLock { $0.append(listener) }
            } else {
                Log.audio.error("Cannot watch the audio devices (\(selector)): \(status)")
            }
        }
    }

    /// After a restart the old listeners are gone already; removing them again returns an error, which is ignored.
    private func removeListeners() {
        let removed = listeners.withLock { listeners in
            defer { listeners = [] }
            return listeners
        }
        for listener in removed {
            var address = listener.address
            AudioObjectRemovePropertyListenerBlock(
                AudioObjectID(kAudioObjectSystemObject), &address, .main, listener.block)
        }
    }

    private func changed(_ change: AudioDevices.Change) {
        if change == .serviceRestarted {
            removeListeners()
            addListeners()
        }
        onChange(change)
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

    enum Change: Sendable {
        /// The default input or output changed (the output feeds the Bluetooth mic warning), or a device connected or
        /// disconnected.
        case devices
        /// The audio service (coreaudiod) restarted, after a crash or `killall coreaudiod`: every device id, unit
        /// and listener from before is stale (AudioHardware.h).
        case serviceRestarted
    }

    static let watchedProperties: [(AudioObjectPropertySelector, Change)] = [
        (kAudioHardwarePropertyDefaultInputDevice, .devices), (kAudioHardwarePropertyDefaultOutputDevice, .devices),
        (kAudioHardwarePropertyDevices, .devices), (kAudioHardwarePropertyServiceRestarted, .serviceRestarted),
    ]

    /// Calls `onChange` on the main queue on each change, until the returned value is released: the app keeps one for
    /// its whole life, a window only while it is open.
    static func observe(_ onChange: @escaping @Sendable (Change) -> Void) -> AudioDeviceObservation {
        AudioDeviceObservation(onChange)
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
