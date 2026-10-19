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
        for _ in 0..<100 { await Task.yield() }
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

    // MARK: Mic test

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
        guard case .running(let levels) = await capture.beginTest(for: .seconds(5)) else {
            Issue.record("The mic test did not start")
            return
        }
        #expect(await eventually { !clock.deadlines.isEmpty })

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
