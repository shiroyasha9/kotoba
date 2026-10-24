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
        #expect(InputDevicePolicy.micInUse(defaultInput: airPods, devices: devices) == builtInMic)
    }

    @Test func theBuiltInMicAsDefaultIsKept() {
        let devices = [builtInMic, builtInSpeakers, airPods]
        #expect(InputDevicePolicy.micInUse(defaultInput: builtInMic, devices: devices) == builtInMic)
    }

    @Test func aWiredMicAsDefaultIsKept() {
        let devices = [builtInMic, usbMic, airPods]
        #expect(InputDevicePolicy.micInUse(defaultInput: usbMic, devices: devices) == usbMic)
    }

    @Test func aDefaultThatIsNotConnectedIsNoMic() {
        #expect(InputDevicePolicy.micInUse(defaultInput: usbMic, devices: [builtInSpeakers]) == nil)
        #expect(InputDevicePolicy.micInUse(defaultInput: nil, devices: [builtInMic]) == nil)
    }

    // MARK: Mics that did not open

    @Test func aListedMicThatDidNotOpenGivesWayToTheNextInTheOrder() {
        let devices = [builtInMic, usbMic, airPods]
        let choice = InputDevicePolicy.micInUse(
            defaultInput: builtInMic, devices: devices, order: ["USBMic", "AirPods"], leftOut: ["USBMic"])
        #expect(choice == airPods)
    }

    @Test func aDefaultThatDidNotOpenLeavesNoMic() {
        let devices = [builtInMic, usbMic]
        #expect(InputDevicePolicy.micInUse(defaultInput: usbMic, devices: devices, leftOut: ["USBMic"]) == nil)
    }

    /// The built-in mic replaced the Bluetooth default; when it does not open, the default stays avoided.
    @Test func aBuiltInMicThatDidNotOpenNeverGivesWayToTheBluetoothDefault() {
        let devices = [builtInMic, airPods]
        #expect(InputDevicePolicy.micInUse(defaultInput: airPods, devices: devices, leftOut: ["BuiltInMic"]) == nil)
    }

    // MARK: Preference order

    @Test func theFirstConnectedDeviceInTheOrderWins() {
        let devices = [builtInMic, usbMic, airPods]
        let order = ["StudioMic", "USBMic", "BuiltInMic"]
        #expect(InputDevicePolicy.micInUse(defaultInput: builtInMic, devices: devices, order: order) == usbMic)
    }

    @Test func aBluetoothMicInTheOrderIsUsedAsListed() {
        let devices = [builtInMic, airPods]
        #expect(
            InputDevicePolicy.micInUse(defaultInput: builtInMic, devices: devices, order: ["AirPods"]) == airPods)
    }

    @Test func withNoListedDeviceConnectedTheDefaultRulesApply() {
        let devices = [builtInMic, airPods]
        let choice = InputDevicePolicy.micInUse(defaultInput: airPods, devices: devices, order: ["StudioMic"])
        #expect(choice == builtInMic)
    }

    @Test func anOutputOnlyDeviceInTheOrderIsSkipped() {
        let devices = [builtInSpeakers, usbMic]
        let choice = InputDevicePolicy.micInUse(
            defaultInput: usbMic, devices: devices, order: ["BuiltInSpeakers"])
        #expect(choice == usbMic)
    }

    // MARK: Bluetooth only when listed (the Microphone page's switch, on by default)

    @Test func anUnlistedBluetoothDefaultIsNeverUsed() {
        let devices = [builtInSpeakers, airPods]
        #expect(InputDevicePolicy.micInUse(defaultInput: airPods, devices: devices) == nil)
        #expect(
            InputDevicePolicy.micInUse(defaultInput: airPods, devices: devices, order: ["StudioMic"]) == nil)
    }

    @Test func aListedBluetoothMicIsUsedWithTheSwitchOn() {
        let devices = [builtInSpeakers, airPods]
        #expect(InputDevicePolicy.micInUse(defaultInput: airPods, devices: devices, order: ["AirPods"]) == airPods)
    }

    @Test func withTheSwitchOffTheBluetoothDefaultIsFollowed() {
        let devices = [builtInMic, airPods]
        let choice = InputDevicePolicy.micInUse(
            defaultInput: airPods, devices: devices, bluetoothOnlyWhenListed: false)
        #expect(choice == airPods)
    }

    @Test func withTheSwitchOffTheOrderStillComesFirst() {
        let devices = [builtInMic, airPods]
        let choice = InputDevicePolicy.micInUse(
            defaultInput: airPods, devices: devices, order: ["BuiltInMic"], bluetoothOnlyWhenListed: false)
        #expect(choice == builtInMic)
    }

    /// A Mac mini with AirPods: the failure names the mic the switch kept out, so the owner can add it.
    @Test func theBluetoothDefaultKeptOutIsNamedOnlyWhenItLeavesNoMic() {
        let macMini = [builtInSpeakers, airPods]
        #expect(InputDevicePolicy.bluetoothKeptOut(defaultInput: airPods, devices: macMini) == airPods)
        #expect(
            InputDevicePolicy.bluetoothKeptOut(defaultInput: airPods, devices: macMini, bluetoothOnlyWhenListed: false)
                == nil)
        #expect(InputDevicePolicy.bluetoothKeptOut(defaultInput: airPods, devices: macMini, order: ["AirPods"]) == nil)
        #expect(InputDevicePolicy.bluetoothKeptOut(defaultInput: airPods, devices: [builtInMic, airPods]) == nil)
        #expect(InputDevicePolicy.bluetoothKeptOut(defaultInput: nil, devices: [builtInSpeakers]) == nil)
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
