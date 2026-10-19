import Foundation
import Synchronization
import Testing

@testable import KotobaCore

/// `make stop-probe` (scripts/stop-probe.sh): the pipeline's own time on the stop path, with every port a fake, so no
/// network, mic, pasteboard or posted event is in it. The interval starts as the stop tap's chord-down goes to
/// `handle` (the stop begins at the chord-down, `PipelineHotkeys.chordDown`) and ends when `FakePaster.sendPaste` runs,
/// where the app posts Cmd-V. The chord-up goes in at once after the chord-down, before the paste's release wait.
/// Each run is a new pipeline after 12 s of recording, with its timers due before the stop and its clipboard restore
/// after the paste. Off unless `KOTOBA_STOP_PROBE_RUNS` is set, so `make test` skips it.
@Suite(.enabled(if: StopProbe.runs != nil))
struct StopProbeTests {
    @Test func stopTapToCommandV() async {
        let runs = StopProbe.runs ?? 0
        for _ in 0..<StopProbe.warmUp {
            _ = await StopProbe.sample()
        }
        var samples: [Duration] = []
        var missed = 0
        for _ in 0..<runs {
            if let sample = await StopProbe.sample() {
                samples.append(sample)
            } else {
                missed += 1
            }
        }
        #expect(missed == 0, "\(missed) of \(runs) stop taps sent no Cmd-V")
        guard !samples.isEmpty else { return }
        samples.sort()
        let line =
            "stop-probe: n=\(samples.count) p50 \(StopProbe.micros(samples, 0.5)) µs, "
            + "p90 \(StopProbe.micros(samples, 0.9)) µs, p99 \(StopProbe.micros(samples, 0.99)) µs\n"
        FileHandle.standardOutput.write(Data(line.utf8))
    }
}

enum StopProbe {
    static let runs = ProcessInfo.processInfo.environment["KOTOBA_STOP_PROBE_RUNS"].flatMap { Int($0) }
    /// Left out of the numbers: the first runs pay for lazy set-up (type metadata, the first tasks of each kind).
    static let warmUp = 100

    /// One dictation: nil when the stop tap sent no Cmd-V.
    static func sample() async -> Duration? {
        let world = FakeWorld(transcript: "a short dictation of about ten words, nothing more")
        let pipeline = world.makePipeline()
        let keyDown = world.clock.now
        await pipeline.tap(world)
        await world.audio.deliverFirstBuffer(at: keyDown + .milliseconds(40))
        world.clock.advance(by: .seconds(12))
        await pipeline.settle()

        let clock = ContinuousClock()
        let sent = Mutex<ContinuousClock.Instant?>(nil)
        await world.paster.whenPasting { sent.withLock { $0 = clock.now } }
        let stop = clock.now
        await pipeline.handle(.chordDown(.tapOrHold))
        await pipeline.handle(.chordUp)
        await pipeline.settle()
        // The clipboard restore waits on the fake clock and holds the pipeline: run it, so no run keeps the last alive.
        world.clock.advance(by: ClipboardPaste.readSettle)
        await pipeline.settle()
        return sent.withLock { $0 }.map { $0 - stop }
    }

    /// The nearest-rank percentile of sorted `samples`, in microseconds with one decimal.
    static func micros(_ samples: [Duration], _ percentile: Double) -> String {
        let rank = min(samples.count - 1, max(0, Int((percentile * Double(samples.count)).rounded(.up)) - 1))
        let (seconds, attoseconds) = samples[rank].components
        return String(format: "%.1f", Double(seconds) * 1e6 + Double(attoseconds) / 1e12)
    }
}
