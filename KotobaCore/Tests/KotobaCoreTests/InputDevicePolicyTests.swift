import Testing

@testable import KotobaCore

struct InputDevicePolicyTests {
    let builtInMic = AudioDevice(
        id: 1, uid: "BuiltInMic", name: "MacBook Pro Microphone", transport: .builtIn, hasInput: true)
    let builtInSpeakers = AudioDevice(
        id: 2, uid: "BuiltInSpeakers", name: "MacBook Pro Speakers", transport: .builtIn, hasInput: false)
    let airPods = AudioDevice(id: 3, uid: "AirPods", name: "AirPods Pro", transport: .bluetooth, hasInput: true)
    let usbMic = AudioDevice(id: 4, uid: "USBMic", name: "USB Microphone", transport: .usb, hasInput: true)

    // MARK: Following the system default (no preference connected)

    @Test func airPodsAsTheDefaultInputSwitchToTheBuiltInMic() {
        let devices = [builtInSpeakers, airPods, builtInMic]
        #expect(InputDevicePolicy.preferredInput(defaultInput: airPods, devices: devices) == builtInMic)
    }

    @Test func theBuiltInMicAsDefaultIsKept() {
        let devices = [builtInMic, builtInSpeakers, airPods]
        #expect(InputDevicePolicy.preferredInput(defaultInput: builtInMic, devices: devices) == nil)
    }

    @Test func aWiredMicAsDefaultIsKept() {
        let devices = [builtInMic, usbMic, airPods]
        #expect(InputDevicePolicy.preferredInput(defaultInput: usbMic, devices: devices) == nil)
    }

    @Test func aMacWithNoBuiltInMicKeepsTheBluetoothDefault() {
        let devices = [builtInSpeakers, airPods]
        #expect(InputDevicePolicy.preferredInput(defaultInput: airPods, devices: devices) == nil)
    }

    // MARK: Preference order

    @Test func theFirstConnectedDeviceInTheOrderWins() {
        let devices = [builtInMic, usbMic, airPods]
        let order = ["StudioMic", "USBMic", "BuiltInMic"]
        #expect(InputDevicePolicy.preferredInput(defaultInput: builtInMic, devices: devices, order: order) == usbMic)
    }

    @Test func aBluetoothMicInTheOrderIsUsedAsListed() {
        let devices = [builtInMic, airPods]
        #expect(
            InputDevicePolicy.preferredInput(defaultInput: builtInMic, devices: devices, order: ["AirPods"]) == airPods)
    }

    @Test func withNoListedDeviceConnectedTheDefaultRulesApply() {
        let devices = [builtInMic, airPods]
        let choice = InputDevicePolicy.preferredInput(defaultInput: airPods, devices: devices, order: ["StudioMic"])
        #expect(choice == builtInMic)
    }

    @Test func anOutputOnlyDeviceInTheOrderIsSkipped() {
        let devices = [builtInSpeakers, usbMic]
        let choice = InputDevicePolicy.preferredInput(
            defaultInput: usbMic, devices: devices, order: ["BuiltInSpeakers"])
        #expect(choice == nil)
    }

    @Test func choosingAMicMovesItToTheTopOfTheOrder() {
        #expect(InputDevicePolicy.order(["A", "B", "C"], choosing: "C") == ["C", "A", "B"])
        #expect(InputDevicePolicy.order(["A", "B"], choosing: "New") == ["New", "A", "B"])
        #expect(InputDevicePolicy.order(["A", "B"], choosing: "A") == ["A", "B"])
    }
}
