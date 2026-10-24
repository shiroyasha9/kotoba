import Testing

@testable import KotobaCore

/// The first launch of 0.5.0 on each kind of Mac. 0.4.6 kept a Bluetooth default on a Mac with no built-in mic, which
/// is the switch off; an update keeps that, whatever is connected at the launch. A new install lists its Bluetooth
/// default.
struct MicrophoneFirstLaunchTests {
    let builtInMic = AudioDevice(
        id: 1, uid: "BuiltInMic", name: "MacBook Pro Microphone", transport: .builtIn, hasInput: true)
    let speakers = AudioDevice(id: 2, uid: "Speakers", name: "Mac mini Speakers", transport: .builtIn, hasInput: false)
    let airPods = AudioDevice(id: 3, uid: "AirPods", name: "AirPods Pro", transport: .bluetooth, hasInput: true)
    let usbMic = AudioDevice(id: 4, uid: "USBMic", name: "USB Microphone", transport: .usb, hasInput: true)

    let fresh = MicrophoneSettings(order: [], bluetoothOnlyWhenListed: true, isFirstLaunchChecked: false)

    /// A login launch or a Sparkle relaunch with the AirPods in their case: the update still turns the switch off, so
    /// the AirPods work when they come back.
    @Test func anUpdateOnAMacMiniWithItsAirPodsAwayTurnsTheSwitchOff() {
        let after = fresh.afterFirstLaunch(isUpdate: true, defaultInput: nil, devices: [speakers])
        #expect(after == MicrophoneSettings(order: [], bluetoothOnlyWhenListed: false, isFirstLaunchChecked: true))
        let later = InputDevicePolicy.micInUse(
            defaultInput: airPods, devices: [speakers, airPods], order: after.order,
            bluetoothOnlyWhenListed: after.bluetoothOnlyWhenListed)
        #expect(later == airPods)
    }

    /// An order whose USB mic is unplugged at the launch: the order stays, and the AirPods default is used as in 0.4.
    @Test func anUpdateKeepsAnOrderWhoseMicIsUnplugged() {
        let before = MicrophoneSettings(order: ["USBMic"], bluetoothOnlyWhenListed: true, isFirstLaunchChecked: false)
        let after = before.afterFirstLaunch(isUpdate: true, defaultInput: airPods, devices: [speakers, airPods])
        #expect(
            after == MicrophoneSettings(order: ["USBMic"], bluetoothOnlyWhenListed: false, isFirstLaunchChecked: true))
        let mic = InputDevicePolicy.micInUse(
            defaultInput: airPods, devices: [speakers, airPods], order: after.order, bluetoothOnlyWhenListed: false)
        #expect(mic == airPods)
    }

    /// A USB mic and AirPods as the default: 0.4 recorded from the AirPods, and so does the update.
    @Test func anUpdateWithAUSBMicAndAirPodsKeepsTheAirPods() {
        let devices = [speakers, usbMic, airPods]
        let after = fresh.afterFirstLaunch(isUpdate: true, defaultInput: airPods, devices: devices)
        #expect(!after.bluetoothOnlyWhenListed)
        #expect(after.order.isEmpty)
        #expect(
            InputDevicePolicy.micInUse(defaultInput: airPods, devices: devices, bluetoothOnlyWhenListed: false)
                == airPods)
    }

    @Test func aNewInstallListsItsConnectedBluetoothDefault() {
        let after = fresh.afterFirstLaunch(isUpdate: false, defaultInput: airPods, devices: [speakers, airPods])
        #expect(
            after == MicrophoneSettings(order: ["AirPods"], bluetoothOnlyWhenListed: true, isFirstLaunchChecked: true))
        let away = fresh.afterFirstLaunch(isUpdate: false, defaultInput: nil, devices: [speakers])
        #expect(away == MicrophoneSettings(order: [], bluetoothOnlyWhenListed: true, isFirstLaunchChecked: true))
    }

    @Test func aMacWithABuiltInMicChangesNothing() {
        let devices = [builtInMic, speakers, airPods]
        let checked = MicrophoneSettings(order: [], bluetoothOnlyWhenListed: true, isFirstLaunchChecked: true)
        #expect(fresh.afterFirstLaunch(isUpdate: true, defaultInput: airPods, devices: devices) == checked)
        #expect(fresh.afterFirstLaunch(isUpdate: false, defaultInput: airPods, devices: devices) == checked)
    }

    /// The flag is set only by a decision: a device list that cannot be read (empty) decides nothing, so the next
    /// launch checks again; once checked, later launches change nothing.
    @Test func theCheckIsMarkedDoneOnlyAfterItsDecision() {
        #expect(fresh.afterFirstLaunch(isUpdate: true, defaultInput: nil, devices: []) == fresh)
        let done = MicrophoneSettings(order: [], bluetoothOnlyWhenListed: true, isFirstLaunchChecked: true)
        #expect(done.afterFirstLaunch(isUpdate: true, defaultInput: airPods, devices: [speakers, airPods]) == done)
    }
}
