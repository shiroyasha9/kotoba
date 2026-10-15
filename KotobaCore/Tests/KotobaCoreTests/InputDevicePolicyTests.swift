import Testing

@testable import KotobaCore

struct InputDevicePolicyTests {
    let builtInMic = AudioDevice(
        id: 1, uid: "BuiltInMic", name: "MacBook Pro Microphone", transport: .builtIn, hasInput: true)
    let builtInSpeakers = AudioDevice(
        id: 2, uid: "BuiltInSpeakers", name: "MacBook Pro Speakers", transport: .builtIn, hasInput: false)
    let airPods = AudioDevice(id: 3, uid: "AirPods", name: "AirPods Pro", transport: .bluetooth, hasInput: true)
    let usbMic = AudioDevice(id: 4, uid: "USBMic", name: "USB Microphone", transport: .usb, hasInput: true)
    let airPodsOutput = AudioDevice(
        id: 5, uid: "AirPodsOut", name: "AirPods Pro", transport: .bluetooth, hasInput: false)

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

    // MARK: Bluetooth warning

    struct WarningCase: Sendable, CustomTestStringConvertible {
        let name: String
        let input: String?
        let output: String?
        let expected: MicrophoneWarning?

        var testDescription: String { name }
    }

    static let warningCases = [
        WarningCase(
            name: "the built-in mic, AirPods playing", input: "BuiltInMic", output: "AirPodsOut", expected: nil),
        WarningCase(name: "a USB mic, AirPods playing", input: "USBMic", output: "AirPodsOut", expected: nil),
        WarningCase(name: "no mic", input: nil, output: "AirPodsOut", expected: nil),
        WarningCase(
            name: "the AirPods mic, AirPods playing", input: "AirPods", output: "AirPodsOut",
            expected: .bluetoothMic(interruptsPlayback: true)),
        WarningCase(
            name: "the AirPods mic, the speakers playing", input: "AirPods", output: "BuiltInSpeakers",
            expected: .bluetoothMic(interruptsPlayback: false)),
        WarningCase(
            name: "the AirPods mic, no output", input: "AirPods", output: nil,
            expected: .bluetoothMic(interruptsPlayback: false)),
    ]

    @Test(arguments: warningCases)
    func aBluetoothMicInUseIsWarnedAbout(_ example: WarningCase) {
        let devices = [builtInMic, builtInSpeakers, airPods, airPodsOutput, usbMic]
        let warning = InputDevicePolicy.warning(
            input: devices.first { $0.uid == example.input },
            outputTransport: devices.first { $0.uid == example.output }?.transport
        )
        #expect(warning == example.expected)
    }
}
