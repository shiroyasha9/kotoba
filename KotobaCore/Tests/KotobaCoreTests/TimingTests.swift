import Foundation
import Testing

@testable import KotobaCore

/// `make timing`: the wall-clock time of work that `make test` checks only by its result (the Polish diff, the
/// dictionary's replacements), against the limits those tests had. Off unless `KOTOBA_TIMING` is set, so `make test`
/// skips it: on a machine busy with other builds a time limit fails while the code is fine.
@Suite(.serialized, .enabled(if: Timing.isOn))
struct TimingTests {
    @Test func aLongPolishDiff() async {
        let (before, after) = WordDiffTests.longPolish()
        await Timing.expect("a 924-word Polish diff", below: .milliseconds(500)) {
            _ = WordDiff.runs(from: before, to: after)
        }
    }

    /// Measured 2026-10-15 (debug build): see the dictionary report.
    @Test func manyRulesOnALongTranscript() async {
        let (dictionary, text) = ReplacementTests.manyRules()
        await Timing.expect("200 replacement rules on 2,000 words", below: .milliseconds(250)) {
            _ = dictionary.applyReplacements(to: text)
        }
    }
}

/// The same in KotobaStorage's `TimingTests.swift` (a test target cannot import another's): change both.
enum Timing {
    static let isOn = ProcessInfo.processInfo.environment["KOTOBA_TIMING"] != nil

    /// Times `body`, prints the time, and records an issue when it is not below `limit`.
    static func expect(_ name: String, below limit: Duration, _ body: () async throws -> Void) async rethrows {
        let time = try await ContinuousClock().measure { try await body() }
        let line = "timing: \(name): \(milliseconds(time)) (limit \(milliseconds(limit)))\n"
        FileHandle.standardOutput.write(Data(line.utf8))
        #expect(time < limit, "\(name)")
    }

    private static func milliseconds(_ time: Duration) -> String {
        time.formatted(.units(allowed: [.milliseconds], width: .abbreviated, fractionalPart: .show(length: 2)))
    }
}
