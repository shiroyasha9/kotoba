import Foundation
import KotobaCore
import Testing

@testable import KotobaProviders

/// The list-price estimate agrees with the `usage.cost` OpenRouter reported in kotoba-bench-v1.
struct PriceListTests {
    @Test func speechCostsTenCentsAnHour() throws {
        #expect(PriceList.estimate(.openRouterMAI, audio: .seconds(36)) == .estimated(try decimal("0.001")))
        #expect(PriceList.estimate(.xaiGrok, audio: .milliseconds(3_600)) == .estimated(try decimal("0.0001")))
    }

    /// Bench: a 1.032 s clip came back as `usage.seconds` 2 on MAI and 1.032 on Grok.
    @Test func maiBillsWholeSecondsAndGrokTheExactLength() {
        #expect(
            PriceList.estimate(.openRouterMAI, audio: .milliseconds(1_032))
                == PriceList.estimate(.openRouterMAI, audio: .seconds(2)))
        #expect(
            PriceList.estimate(.azureMAI, audio: .milliseconds(1_032))
                == PriceList.estimate(.azureMAI, audio: .seconds(2)))
        #expect(
            PriceList.estimate(.openRouterGrok, audio: .milliseconds(1_032))
                == .estimated(Decimal(10_320) / 360_000_000))
    }

    @Test(arguments: [
        (CleanupModel.qwenCerebras, 460, 9, "0.00046881"),
        (.claudeHaiku, 753, 96, "0.0001233"),
        (.geminiFlashLite, 438, 6, "0.0001464"),
    ])
    func cleanupCostsItsTokens(model: CleanupModel, input: Int, output: Int, reported: String) throws {
        #expect(
            PriceList.estimate(model, inputTokens: input, outputTokens: output) == .estimated(try decimal(reported)))
    }

    private func decimal(_ text: String) throws -> Decimal {
        try #require(Decimal(string: text))
    }
}
