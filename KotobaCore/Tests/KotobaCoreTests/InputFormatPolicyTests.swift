import Testing

@testable import KotobaCore

struct InputFormatPolicyTests {
    struct Case: Sendable, CustomTestStringConvertible {
        let name: String
        let sampleRate: Double
        let channelCount: UInt32
        let deviceSampleRate: Double?
        let expected: InputFormatPolicy.Rejection?

        var testDescription: String { name }
    }

    static let cases: [Case] = [
        Case(
            name: "the built-in mic, input and device agree",
            sampleRate: 48_000, channelCount: 1, deviceSampleRate: 48_000, expected: nil),
        Case(
            name: "a two-channel USB mic, input and device agree",
            sampleRate: 48_000, channelCount: 2, deviceSampleRate: 48_000, expected: nil),
        Case(
            name: "AirPods in the call profile, input and device agree",
            sampleRate: 24_000, channelCount: 1, deviceSampleRate: 24_000, expected: nil),
        Case(
            name: "no input device: zero rate",
            sampleRate: 0, channelCount: 0, deviceSampleRate: 48_000, expected: .noAudio),
        Case(
            name: "a device mid-change: a rate but no channels",
            sampleRate: 48_000, channelCount: 0, deviceSampleRate: 48_000, expected: .noAudio),
        Case(
            name: "a device mid-change: the hardware format has the new rate, the device the old one",
            sampleRate: 48_000, channelCount: 2, deviceSampleRate: 24_000,
            expected: .deviceChanged(inputRate: 48_000, deviceRate: 24_000)),
        Case(
            name: "the device went away",
            sampleRate: 48_000, channelCount: 1, deviceSampleRate: nil, expected: .deviceGone),
    ]

    @Test(arguments: cases)
    func rejection(_ example: Case) {
        let rejection = InputFormatPolicy.rejection(
            sampleRate: example.sampleRate,
            channelCount: example.channelCount,
            deviceSampleRate: example.deviceSampleRate
        )
        #expect(rejection == example.expected)
    }

    struct RecoveryCase: Sendable, CustomTestStringConvertible {
        let name: String
        let rejection: InputFormatPolicy.Rejection?
        let attempt: Int
        let expected: InputRecovery

        var testDescription: String { name }
    }

    static let recoveryCases = [
        RecoveryCase(
            name: "a rate change on the first try is tried once more",
            rejection: .deviceChanged(inputRate: 48_000, deviceRate: 44_100), attempt: 1, expected: .retry),
        RecoveryCase(
            name: "a rate change on the second try stops, no other mic",
            rejection: .deviceChanged(inputRate: 48_000, deviceRate: 44_100), attempt: 2, expected: .stop),
        RecoveryCase(
            name: "no audio on the first try is tried once more", rejection: .noAudio, attempt: 1, expected: .retry),
        RecoveryCase(name: "no audio on the second try stops", rejection: .noAudio, attempt: 2, expected: .stop),
        RecoveryCase(
            name: "a mic that went away: choose another", rejection: .deviceGone, attempt: 1, expected: .chooseAnother),
        RecoveryCase(
            name: "the input unit failed: choose another", rejection: nil, attempt: 1, expected: .chooseAnother),
    ]

    @Test(arguments: recoveryCases)
    func recovery(_ example: RecoveryCase) {
        #expect(InputFormatPolicy.recovery(after: example.rejection, attempt: example.attempt) == example.expected)
    }
}
