import Foundation
import Synchronization
import Testing

@testable import KotobaCore

/// The mic input's lifecycle: which mic records, when its input is built again, and what waits for the end of a
/// capture. Device, route and settling events in through the fake hardware, the capture's calls in through
/// `AudioSource`; assertions on the inputs that opened and ran and on what the recorders saw.
///
/// The regressions of 2026-10-17 each have a test here: 2c207aa (a start that fails, a coreaudiod restart), 918babc
/// (a cancel during a rebuild's rate switch), 09ea89c (a stop with no input running, an Undo during a rebuild) and
/// f681363 (a mic read twice in the middle of a change).
struct AudioCaptureTests {
    private static let file = URL.temporaryDirectory.appending(path: "kotoba-capture-test.flac")
    private static let changing = InputFormatPolicy.Rejection.deviceChanged(inputRate: 44_100, deviceRate: 48_000)

    private struct UnitFailure: Error {}

    // MARK: Start and stop

    @Test func aPressStartsThePreparedInputAndTheStopKeepsTheLastCycle() async throws {
        let hardware = FakeCaptureHardware()
        let capture = AudioCapture(hardware: hardware)

        await capture.prepare()
        #expect(hardware.opened == ["built-in"])
        #expect(hardware.running == nil)

        _ = try await capture.beginCapture(into: Self.file)
        #expect(hardware.running?.device == FakeCaptureHardware.builtIn)
        #expect(hardware.recorders.first?.isStarted == true)

        _ = await capture.endCapture()
        #expect(hardware.recorders.first?.stops == [.afterCycle])
        #expect(await eventually { hardware.running == nil })
        #expect(hardware.opened == ["built-in"])
    }

    @Test func aPreparedInputThatDoesNotStartIsBuiltAgainInTheSamePress() async throws {
        let hardware = FakeCaptureHardware()
        hardware.failStarts(of: FakeCaptureHardware.builtIn)
        let capture = AudioCapture(hardware: hardware)
        await capture.prepare()

        _ = try await capture.beginCapture(into: Self.file)

        #expect(hardware.opened == ["built-in", "built-in"])
        #expect(hardware.running === hardware.inputs.last)
    }

    @Test func aSecondFailedStartGoesToThePipelineAndTheNextPressBuildsAgain() async throws {
        let hardware = FakeCaptureHardware()
        hardware.failStarts(of: FakeCaptureHardware.builtIn, inputs: 2)
        let capture = AudioCapture(hardware: hardware)
        await capture.prepare()

        await #expect(throws: FakeCaptureInput.StartFailure.self) {
            _ = try await capture.beginCapture(into: Self.file)
        }
        #expect(hardware.recorders.isEmpty)

        _ = try await capture.beginCapture(into: Self.file)
        #expect(hardware.opened == ["built-in", "built-in", "built-in"])
        #expect(hardware.running != nil)
    }

    /// One capture at a time: a begin during a capture or its Undo window is refused, and the first goes on.
    @Test func aBeginDuringACaptureIsRefusedAndTheFirstGoesOn() async throws {
        let hardware = FakeCaptureHardware()
        let capture = AudioCapture(hardware: hardware)
        _ = try await capture.beginCapture(into: Self.file)

        await #expect(throws: AudioCapture.CaptureError.alreadyCapturing) {
            _ = try await capture.beginCapture(into: Self.file)
        }
        await capture.pauseCapture()
        await #expect(throws: AudioCapture.CaptureError.alreadyCapturing) {
            _ = try await capture.beginCapture(into: Self.file)
        }
        #expect(hardware.running == nil)
        try await capture.resumeCapture()

        #expect(hardware.recorders.count == 1)
        #expect(hardware.recorders.first?.stops.isEmpty == true)
        #expect(hardware.running != nil)
        _ = await capture.endCapture()
        #expect(hardware.recorders.first?.stops == [.afterCycle])
    }

    @Test func anAudioServiceRestartBuildsTheInputAgain() async {
        let hardware = FakeCaptureHardware()
        let capture = AudioCapture(hardware: hardware)
        await capture.prepare()

        hardware.restartService()

        #expect(await eventually { hardware.opened.count == 2 && hardware.inputs.count == 1 })
    }

    // MARK: Route changes during a capture

    @Test func aRouteChangeMidCaptureSwitchesTheRecorderThenStartsTheNewInput() async throws {
        let hardware = FakeCaptureHardware()
        let capture = AudioCapture(hardware: hardware)
        _ = try await capture.beginCapture(into: Self.file)

        hardware.setSampleRate(24_000, of: FakeCaptureHardware.builtIn)
        hardware.running?.changeRoute()

        #expect(await eventually { hardware.running?.sampleRate == 24_000 })
        #expect(hardware.recorders.first?.rates == [48_000, 24_000])
        #expect(hardware.inputs.count == 1)
    }

    @Test func losingTheMicInUseDuringACaptureSwitchesAtOnce() async throws {
        let hardware = FakeCaptureHardware(devices: [FakeCaptureHardware.usb, FakeCaptureHardware.builtIn])
        hardware.setOrder(["usb"])
        let capture = AudioCapture(hardware: hardware)
        await capture.prepare()
        _ = try await capture.beginCapture(into: Self.file)

        hardware.disconnect(FakeCaptureHardware.usb)

        #expect(await eventually { hardware.running?.device == FakeCaptureHardware.builtIn })
        #expect(capture.inputInUse == FakeCaptureHardware.builtIn)
        #expect(hardware.recorders.count == 1)
    }

    /// The owner's case (plan, "Microphone"): the listed USB mic is unplugged mid-dictation and macOS moves the default
    /// to the AirPods. The built-in mic takes over; the AirPods, not in the list, never open.
    @Test func anUnpluggedMicNeverGivesWayToAnUnlistedBluetoothDefault() async throws {
        let hardware = FakeCaptureHardware(
            devices: [FakeCaptureHardware.usb, FakeCaptureHardware.airPods, FakeCaptureHardware.builtIn],
            defaultInput: FakeCaptureHardware.usb)
        hardware.setOrder(["usb"])
        let capture = AudioCapture(hardware: hardware)
        await capture.prepare()
        _ = try await capture.beginCapture(into: Self.file)

        hardware.disconnect(FakeCaptureHardware.usb)

        #expect(await eventually { hardware.running?.device == FakeCaptureHardware.builtIn })
        #expect(hardware.defaultInput() == FakeCaptureHardware.airPods)
        #expect(!hardware.opened.contains("airpods"))
    }

    /// The same unplug with no other mic but the AirPods: the dictation hears the loss, and the AirPods never open.
    @Test func anUnpluggedMicWithOnlyAnUnlistedBluetoothMicLeftIsALoss() async throws {
        let hardware = FakeCaptureHardware(
            devices: [FakeCaptureHardware.usb, FakeCaptureHardware.airPods], defaultInput: FakeCaptureHardware.usb)
        hardware.setOrder(["usb"])
        let capture = AudioCapture(hardware: hardware)
        await capture.prepare()
        let events = try await capture.beginCapture(into: Self.file)

        hardware.disconnect(FakeCaptureHardware.usb)

        #expect(await eventually { capture.inputInUse == nil })
        _ = await capture.endCapture()
        #expect(await finished(events) == [.inputLost])
        #expect(hardware.opened == ["usb"])
    }

    @Test func aMicLostWithNoOtherIsReportedOnceUntilANewMicOpens() async throws {
        let hardware = FakeCaptureHardware()
        let capture = AudioCapture(hardware: hardware)
        await capture.prepare()
        let events = try await capture.beginCapture(into: Self.file)

        hardware.disconnect(FakeCaptureHardware.builtIn)
        #expect(await eventually { capture.inputInUse == nil })
        // A rebuild with still no mic says nothing more: the events at the end are exactly two losses.
        let reads = hardware.deviceReads
        hardware.restartService()
        #expect(await eventually { hardware.deviceReads > reads })
        hardware.connect(FakeCaptureHardware.builtIn)
        #expect(await eventually { hardware.running != nil })
        hardware.disconnect(FakeCaptureHardware.builtIn)
        #expect(await eventually { hardware.running == nil && capture.inputInUse == nil })
        _ = await capture.endCapture()

        #expect(await finished(events) == [.inputLost, .inputLost])
    }

    @Test func aStopWithNoInputRunningWritesWhatArrivedAtOnce() async throws {
        let hardware = FakeCaptureHardware()
        let capture = AudioCapture(hardware: hardware)
        _ = try await capture.beginCapture(into: Self.file)

        hardware.disconnect(FakeCaptureHardware.builtIn)
        #expect(await eventually { capture.inputInUse == nil })
        _ = await capture.endCapture()

        #expect(hardware.recorders.first?.stops == [.now])
    }

    @Test func aStopDuringARebuildWritesWhatArrivedAtOnce() async throws {
        let hardware = FakeCaptureHardware()
        hardware.holdRateSwitches()
        let capture = AudioCapture(hardware: hardware)
        _ = try await capture.beginCapture(into: Self.file)
        let recorder = try #require(hardware.recorders.first)

        hardware.running?.changeRoute()
        #expect(await eventually { await recorder.hasHeldSwitch })
        _ = await capture.endCapture()

        #expect(recorder.stops == [.now])
    }

    @Test func aCancelDuringARebuildsRateSwitchLeavesLaterRouteChangesWorking() async throws {
        let hardware = FakeCaptureHardware()
        hardware.holdRateSwitches()
        let capture = AudioCapture(hardware: hardware)
        _ = try await capture.beginCapture(into: Self.file)
        let recorder = try #require(hardware.recorders.first)

        hardware.running?.changeRoute()
        #expect(await eventually { await recorder.hasHeldSwitch })
        _ = await capture.cancelCapture()

        // The input built for the cancelled capture stays off.
        #expect(await eventually { hardware.opened.count == 2 })
        #expect(hardware.running == nil)
        hardware.inputs.last?.changeRoute()
        #expect(await eventually { hardware.opened.count == 3 })
    }

    // MARK: Undo

    @Test func anUndoDuringARebuildStartsTheNewInputAfterTheRateSwitch() async throws {
        let hardware = FakeCaptureHardware()
        hardware.holdRateSwitches()
        let capture = AudioCapture(hardware: hardware)
        _ = try await capture.beginCapture(into: Self.file)
        let recorder = try #require(hardware.recorders.first)
        await capture.pauseCapture()

        hardware.inputs.last?.changeRoute()
        #expect(await eventually { await recorder.hasHeldSwitch })
        let isResumed = Mutex(false)
        let resumed = Task {
            try await capture.resumeCapture()
            isResumed.withLock { $0 = true }
        }
        #expect(await eventually { await capture.rebuildWaiterCount == 1 })
        #expect(hardware.running == nil)

        await recorder.releaseRateSwitch()
        // Bounded: a resume that never wakes fails here instead of hanging the run.
        try #require(await eventually { isResumed.withLock { $0 } })
        try await resumed.value

        #expect(hardware.opened.count == 2)
        #expect(hardware.running === hardware.inputs.last)
        #expect(recorder.stops.isEmpty)
    }

    @Test func anUndoWhoseMicDoesNotStartBuildsTheInputAgainAtTheRecordersRate() async throws {
        let hardware = FakeCaptureHardware()
        let capture = AudioCapture(hardware: hardware)
        _ = try await capture.beginCapture(into: Self.file)
        await capture.pauseCapture()

        hardware.setSampleRate(44_100, of: FakeCaptureHardware.builtIn)
        hardware.inputs.last?.failNextStart()
        try await capture.resumeCapture()

        #expect(hardware.opened.count == 2)
        #expect(hardware.running?.sampleRate == 44_100)
        #expect(hardware.recorders.first?.rates == [48_000, 44_100])
    }

    // MARK: A mic in the middle of a change

    @Test func aMicReadTwiceMidChangeWaitsForItsChangeAndOpensNoOtherMic() async throws {
        // AirPods are the system default; the Bluetooth rule records from the built-in mic.
        let hardware = FakeCaptureHardware(
            devices: [FakeCaptureHardware.builtIn, FakeCaptureHardware.airPods],
            defaultInput: FakeCaptureHardware.airPods)
        let capture = AudioCapture(hardware: hardware)
        let events = try await capture.beginCapture(into: Self.file)
        #expect(hardware.running?.device == FakeCaptureHardware.builtIn)

        hardware.failOpens(of: FakeCaptureHardware.builtIn, with: [Self.changing, Self.changing])
        hardware.running?.changeRoute()
        #expect(await eventually { hardware.watchedForSettling == ["built-in"] })
        #expect(hardware.running == nil)
        #expect(!hardware.opened.contains("airpods"))

        hardware.finishChange(of: FakeCaptureHardware.builtIn)
        #expect(await eventually { hardware.running?.device == FakeCaptureHardware.builtIn })
        #expect(hardware.watchedForSettling.isEmpty)
        _ = await capture.endCapture()

        #expect(await finished(events) == [.inputLost])
        #expect(hardware.recorders.first?.rates == [48_000, 48_000])
    }

    @Test func aMicReadOnceMidChangeOpensAgainAtOnce() async {
        let hardware = FakeCaptureHardware()
        hardware.failOpens(of: FakeCaptureHardware.builtIn, with: [Self.changing])
        let capture = AudioCapture(hardware: hardware)

        await capture.prepare()

        #expect(hardware.opened == ["built-in"])
        #expect(capture.inputInUse == FakeCaptureHardware.builtIn)
        #expect(hardware.watchedForSettling.isEmpty)
    }

    @Test func aMicThatDoesNotOpenIsLeftOutForTheNextInOrder() async {
        let hardware = FakeCaptureHardware(devices: [FakeCaptureHardware.usb, FakeCaptureHardware.builtIn])
        hardware.setOrder(["usb", "built-in"])
        hardware.failOpens(of: FakeCaptureHardware.usb, with: [UnitFailure()])
        let capture = AudioCapture(hardware: hardware)

        await capture.prepare()

        #expect(hardware.opened == ["built-in"])
        #expect(capture.inputInUse == FakeCaptureHardware.builtIn)
    }

    /// The Bluetooth rule replaced the AirPods default by the built-in mic; when that does not open, the AirPods stay
    /// closed too (no call profile), and the press says no mic opened.
    @Test func aBuiltInMicThatDoesNotOpenNeverOpensTheBluetoothDefault() async {
        let hardware = FakeCaptureHardware(
            devices: [FakeCaptureHardware.builtIn, FakeCaptureHardware.airPods],
            defaultInput: FakeCaptureHardware.airPods)
        hardware.failOpens(of: FakeCaptureHardware.builtIn, with: [UnitFailure(), UnitFailure()])
        let capture = AudioCapture(hardware: hardware)

        await capture.prepare()
        #expect(hardware.opened.isEmpty)
        #expect(capture.inputInUse == nil)

        await #expect(throws: AudioCapture.CaptureError.noInputDevice) {
            _ = try await capture.beginCapture(into: Self.file)
        }
        #expect(hardware.opened.isEmpty)
    }
}
