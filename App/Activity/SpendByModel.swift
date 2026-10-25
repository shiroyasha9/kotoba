import Foundation
import KotobaCore
import KotobaProviders
import KotobaStorage
import SwiftUI

/// This month's spend by model, in Activity's "Advanced…" sheet (docs/research/ui-redesign.md, "Advanced controls"):
/// what each speech, cleanup and polish model billed, to the fraction of a cent, rounded so the rows add up to the total
/// under them (the page shows the total in cents).
struct SpendByModel: View {
    let month: UsageSummary

    var body: some View {
        let amounts = DollarAmounts(month)
        PageSheet(title: "Spend by Model") {
            Section {
                ForEach(month.models) { spend in
                    PageRow(title: Self.title(of: spend), subtitle: Self.detail(of: spend)) {
                        Text(spend.cost == 0 && spend.unpricedAnswers > 0 ? "Unknown" : amounts.part(spend.id))
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                    }
                }
                // In the primary colour, apart from the rows it adds up, as Battery's and Storage's totals.
                LabeledContent("Total") {
                    Text(amounts.total)
                        .monospacedDigit()
                        .foregroundStyle(.primary)
                }
            } header: {
                Text("This Month by Model")
            }
        }
    }

    /// "Speech model · Estimated · Cost unknown for 3 requests".
    private static func detail(of spend: ModelSpend) -> String {
        [
            role(of: spend.kind),
            spend.isEstimated ? "Estimated" : nil,
            spend.unpricedAnswers > 0 ? unpricedNote(spend.unpricedAnswers) : nil,
        ]
        .compactMap(\.self).joined(separator: " · ")
    }

    /// What the model does, the line under its name.
    private static func role(of kind: UsageEntry.Kind) -> String {
        switch kind {
        case .speech: "Speech model"
        case .cleanup: "Cleanup model"
        case .polish: "Rewrite model"
        }
    }

    /// The model's display name; a model kotoba no longer offers gets a generic one, never its identifier.
    private static func title(of spend: ModelSpend) -> String {
        switch spend.kind {
        case .cleanup:
            CleanupModel(rawValue: spend.model)?.title ?? "Earlier cleanup model"
        case .speech:
            TranscriptionRoute(rawValue: spend.model)?.title ?? "Earlier speech model"
        case .polish:
            PolishModel(rawValue: spend.model)?.title ?? "Earlier rewrite model"
        }
    }

    /// Answers kept before kotoba recorded costs, or a rare answer with no cost and no token counts.
    private static func unpricedNote(_ count: Int) -> String {
        "Cost unknown for \(StatusText.counted(count, "request"))"
    }
}

/// Dollar amounts as Activity shows them: up to four decimals under $1 (a dictation costs a fraction of a cent), else
/// cents.
/// The model rows are rounded so they add up to the rounded total: each is rounded down, and the units left go to
/// the rows that lost the most (largest remainder).
struct DollarAmounts {
    let total: String
    private let parts: [String: String]

    init(_ summary: UsageSummary) {
        let digits = summary.cost < 1 ? 4 : 2
        let unit = Self.unit(digits)
        let roundedTotal = Self.rounded(summary.cost, digits, .plain)
        var parts = summary.models.map { (id: $0.id, floor: Self.rounded($0.cost, digits, .down), cost: $0.cost) }
        var left = (roundedTotal - parts.reduce(0) { $0 + $1.floor }) / unit
        for index in parts.indices.sorted(by: { parts[$0].cost - parts[$0].floor > parts[$1].cost - parts[$1].floor })
        where left > 0 {
            parts[index].floor += unit
            left -= 1
        }
        let format = Decimal.FormatStyle.Currency(code: "USD").precision(.fractionLength(2...digits))
        total = roundedTotal.formatted(format)
        self.parts = Dictionary(uniqueKeysWithValues: parts.map { ($0.id, $0.floor.formatted(format)) })
    }

    func part(_ id: String) -> String {
        parts[id] ?? ""
    }

    private static func unit(_ digits: Int) -> Decimal {
        Decimal(sign: .plus, exponent: -digits, significand: 1)
    }

    private static func rounded(_ value: Decimal, _ digits: Int, _ mode: Decimal.RoundingMode) -> Decimal {
        var value = value
        var result = Decimal()
        NSDecimalRound(&result, &value, digits, mode)
        return result
    }
}
