import Foundation
import KotobaCore

/// List prices for a cost estimate when an answer reports no cost: the direct xAI and Azure routes never do, and an
/// OpenRouter answer without `usage.cost` falls back to it. Checked 2026-10-16:
/// - OpenRouter: `GET https://openrouter.ai/api/v1/models/<slug>/endpoints`. MAI-Transcribe-2 `prompt` "0.1" and Grok
///   STT `prompt` "0.0000277777777778" per second, both $0.10 per audio hour (kotoba-bench-v1's `usage.cost` per
///   `usage.seconds` agrees for both); Gemini 3.5 Flash-Lite $0.30 / $2.50, Qwen 3.8 27B on Cerebras $0.99 / $1.49,
///   Claude Haiku 5.5 $0.10 / $0.50 per 1M input / output tokens (Haiku costs more past 100k prompt tokens, which
///   a dictation never reaches).
/// - xAI: https://docs.x.ai/developers/models, speech to text over REST $0.10 per hour.
/// - Azure: https://azure.microsoft.com/en-us/pricing/details/speech/, MAI-Transcribe-2 is a promotion until
///   2026-12-31, billed in second increments; the page shows no number, so OpenRouter's $0.10 per hour for its one
///   (Azure) endpoint stands in. Check after 2026-12-31 (docs/spec.md, unresolved question 1).
enum PriceList {
    /// US cents per audio hour for each speech route.
    static func centsPerHour(_ route: TranscriptionRoute) -> Int {
        switch route {
        case .openRouterMAI, .openRouterGrok, .xaiGrok, .azureMAI: 10
        }
    }

    /// MAI-Transcribe-2 bills whole seconds: OpenRouter's `usage.seconds` was each clip's length rounded up in
    /// kotoba-bench-v1 (1.032 s billed as 2 s), and Azure bills "in second increments". Grok bills the exact length.
    static func billed(_ audio: Duration, on route: TranscriptionRoute) -> Duration {
        guard !route.isGrok else { return audio }
        return .seconds((audio / .seconds(1)).rounded(.up))
    }

    static func estimate(_ route: TranscriptionRoute, audio: Duration) -> Cost {
        let milliseconds = Int((billed(audio, on: route) / .milliseconds(1)).rounded())
        // One division at the end: cents per hour to dollars per millisecond.
        return .estimated(Decimal(milliseconds * centsPerHour(route)) / 360_000_000)
    }

    /// US cents per 1M input and output tokens.
    static func centsPerMillionTokens(_ model: CleanupModel) -> (input: Int, output: Int) {
        switch model {
        case .deepSeekFlash: (30, 120)
        case .geminiFlashLite: (30, 250)
        case .qwenCerebras: (99, 149)
        case .claudeHaiku: (10, 50)
        }
    }

    /// `outputTokens` includes reasoning tokens, as OpenRouter's `completion_tokens` does.
    static func estimate(_ model: CleanupModel, inputTokens: Int, outputTokens: Int) -> Cost {
        estimate(centsPerMillionTokens(model), inputTokens: inputTokens, outputTokens: outputTokens)
    }

    /// Polish (`GET /models/<slug>/endpoints`, 2026-10-17): Together, PrimeIntellect and InferenceNet ask at most
    /// $0.30 / $1.20 per 1M tokens for DeepSeek V4.1 Flash; Gemini as for cleanup.
    static func estimate(_ model: PolishModel, inputTokens: Int, outputTokens: Int) -> Cost {
        let price =
            switch model {
            case .deepSeekFlash: centsPerMillionTokens(.deepSeekFlash)
            case .geminiFlashLite: centsPerMillionTokens(.geminiFlashLite)
            }
        return estimate(price, inputTokens: inputTokens, outputTokens: outputTokens)
    }

    private static func estimate(_ price: (input: Int, output: Int), inputTokens: Int, outputTokens: Int) -> Cost {
        .estimated(Decimal(inputTokens * price.input + outputTokens * price.output) / 100_000_000)
    }
}

extension TranscriptionUsage {
    /// What a route's answer reported, with the `recorded` length for a missing audio count and the list price for a
    /// missing cost.
    static func priced(
        audio: Duration?, cost: Decimal?, recorded: Duration, on route: TranscriptionRoute
    ) -> Self {
        let audio = audio ?? recorded
        return Self(audio: audio, cost: cost.map(Cost.reported) ?? PriceList.estimate(route, audio: audio))
    }
}
