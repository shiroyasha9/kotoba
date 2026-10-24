import Foundation

/// The mic `AudioCapture` records from: the owner's order and the system default, through `InputDevicePolicy`.
extension AudioCapture {
    /// The mic to record from among `devices`, without the ones in `leftOut`: the first one in the owner's order, else
    /// the system default (a Bluetooth default replaced by the built-in mic while the owner's switch says so,
    /// `InputDevicePolicy`).
    func micInUse(among devices: [AudioDevice], leftOut: Set<String> = []) -> AudioDevice? {
        InputDevicePolicy.micInUse(
            defaultInput: hardware.defaultInput(), devices: devices, order: hardware.microphoneOrder(),
            leftOut: leftOut, bluetoothOnlyWhenListed: hardware.bluetoothOnlyWhenListed())
    }

    /// Why no mic opened: a Bluetooth mic the owner's switch keeps out, by name, else no input. Read only on a failed
    /// press.
    func noMicError() -> CaptureError {
        let keptOut = InputDevicePolicy.bluetoothKeptOut(
            defaultInput: hardware.defaultInput(), devices: hardware.devices(), order: hardware.microphoneOrder(),
            bluetoothOnlyWhenListed: hardware.bluetoothOnlyWhenListed())
        return keptOut.map { .bluetoothNotListed(name: $0.name) } ?? .noInputDevice
    }
}
