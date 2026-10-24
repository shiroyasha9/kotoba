import Foundation
import Testing

@testable import KotobaCore

/// Mic choice changes and the Settings mic test: what switches at once, what waits for the end of a capture, and what
/// ends a test.
struct AudioCaptureChangeTests {
    private static let file = URL.temporaryDirectory.appending(path: "kotoba-capture-change-test.flac")

    // MARK: Changes that wait for the end of a capture

    @Test func aMicReorderDuringACaptureWaitsForTheCaptureEnd() async throws {
        let hardware = FakeCaptureHardware(devices: [FakeCaptureHardware.builtIn, FakeCaptureHardware.usb])
        let capture = AudioCapture(hardware: hardware)
        await capture.prepare()
        _ = try await capture.beginCapture(into: Self.file)

        hardware.setOrder(["usb"])
        await capture.inputMayHaveChanged()
        #expect(hardware.opened == ["built-in"])
        #expect(hardware.running?.device == FakeCaptureHardware.builtIn)

        _ = await capture.endCapture()
        #expect(await eventually { capture.inputInUse == FakeCaptureHardware.usb })
        #expect(hardware.running == nil)
    }

    @Test func aMicConnectedDuringACaptureIsUsedFromTheNextDictation() async throws {
        let hardware = FakeCaptureHardware()
        hardware.setOrder(["usb"])
        let capture = AudioCapture(hardware: hardware)
        await capture.prepare()
        _ = try await capture.beginCapture(into: Self.file)

        hardware.connect(FakeCaptureHardware.usb)
        #expect(await eventually { await capture.isInputChangeDeferred })
        #expect(hardware.opened == ["built-in"])

        _ = await capture.cancelCapture()
        #expect(await eventually { capture.inputInUse == FakeCaptureHardware.usb })
    }

    @Test func aChangeWhileIdleRebuildsAtOnceOnlyWhenTheChoiceChanges() async {
        let hardware = FakeCaptureHardware()
        let capture = AudioCapture(hardware: hardware)
        await capture.prepare()

        hardware.connect(FakeCaptureHardware.usb)
        await capture.inputMayHaveChanged()
        #expect(hardware.opened == ["built-in"])

        hardware.setOrder(["usb"])
        await capture.inputMayHaveChanged()
        #expect(hardware.opened == ["built-in", "usb"])
        #expect(hardware.inputs.count == 1)
    }

    @Test func theBluetoothSwitchChangesTheMicAtTheNextChoice() async {
        let hardware = FakeCaptureHardware(
            devices: [FakeCaptureHardware.builtIn, FakeCaptureHardware.airPods],
            defaultInput: FakeCaptureHardware.airPods)
        let capture = AudioCapture(hardware: hardware)
        await capture.prepare()
        #expect(hardware.opened == ["built-in"])

        hardware.setBluetoothOnlyWhenListed(false)
        await capture.inputMayHaveChanged()
        #expect(hardware.opened == ["built-in", "airpods"])
        #expect(capture.inputInUse == FakeCaptureHardware.airPods)
    }

    @Test func aMacWithOnlyAnUnlistedBluetoothMicFailsWithItsName() async {
        let hardware = FakeCaptureHardware(
            devices: [FakeCaptureHardware.airPods], defaultInput: FakeCaptureHardware.airPods)
        let capture = AudioCapture(hardware: hardware)
        await capture.prepare()

        await #expect(throws: AudioCapture.CaptureError.bluetoothNotListed(name: "AirPods Pro")) {
            try await capture.beginCapture(into: Self.file)
        }
        #expect(hardware.opened.isEmpty)

        hardware.setOrder(["airpods"])
        await capture.inputMayHaveChanged()
        _ = try? await capture.beginCapture(into: Self.file)
        #expect(hardware.opened == ["airpods"])
        _ = await capture.cancelCapture()
    }

    // MARK: Mic test

    @Test func theMicTestNamesABluetoothMicTheSwitchKeepsOut() async {
        let hardware = FakeCaptureHardware(
            devices: [FakeCaptureHardware.airPods], defaultInput: FakeCaptureHardware.airPods)
        let capture = AudioCapture(hardware: hardware)
        await capture.prepare()

        guard case .blocked(.bluetoothNotListed("AirPods Pro")) = await capture.beginTest(for: .seconds(5)) else {
            Issue.record("The mic test did not name the Bluetooth mic")
            return
        }
    }

    @Test func aDictationEndsTheMicTestAndRecordsOnTheSameMic() async throws {
        let hardware = FakeCaptureHardware()
        let capture = AudioCapture(hardware: hardware, clock: ManualClock())
        await capture.prepare()
        guard case .running(let levels) = await capture.beginTest(for: .seconds(5)) else {
            Issue.record("The mic test did not start")
            return
        }

        _ = try await capture.beginCapture(into: Self.file)

        #expect(await finished(levels) != nil)
        #expect(hardware.recorders.first?.stops == [.now])
        #expect(hardware.recorders.count == 2)
        #expect(hardware.running != nil)
        #expect(hardware.opened == ["built-in"])
    }

    @Test func theMicTestEndsAfterItsDuration() async {
        let hardware = FakeCaptureHardware()
        let clock = ManualClock()
        let capture = AudioCapture(hardware: hardware, clock: clock)
        let start = clock.now
        guard case .running(let levels) = await capture.beginTest(for: .seconds(5)) else {
            Issue.record("The mic test did not start")
            return
        }
        await clock.waitForTimer(at: start + .seconds(5))

        clock.advance(by: .seconds(5))

        #expect(await finished(levels) != nil)
        #expect(hardware.recorders.first?.stops == [.now])
        #expect(await eventually { hardware.running == nil })
    }

    @Test func noMicTestDuringADictation() async throws {
        let hardware = FakeCaptureHardware()
        let capture = AudioCapture(hardware: hardware, clock: ManualClock())
        _ = try await capture.beginCapture(into: Self.file)

        guard case .blocked(.dictating) = await capture.beginTest(for: .seconds(5)) else {
            Issue.record("The mic test started during a dictation")
            return
        }
        #expect(hardware.recorders.count == 1)
    }

    @Test func noMicTestWithoutAMic() async {
        let hardware = FakeCaptureHardware(devices: [], defaultInput: nil)
        let capture = AudioCapture(hardware: hardware, clock: ManualClock())

        guard case .blocked(.noInput) = await capture.beginTest(for: .seconds(5)) else {
            Issue.record("The mic test started with no mic")
            return
        }
        #expect(hardware.recorders.isEmpty)
    }
}
