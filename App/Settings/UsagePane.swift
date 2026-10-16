import AppKit
import KotobaCore
import KotobaProviders
import KotobaStorage
import Observation
import SwiftUI

extension Pane {
    static func usage(_ model: UsageModel) -> Self {
        Pane(id: .usage) {
            AnyView(UsagePane(model: model))
        }
    }
}

/// How much the owner dictates and what it costs, this month and in the last 30 days. Built with each Settings
/// window; it reads the usage ledger when the pane appears and after each history write while it is shown (three
/// SQLite statements per period), so nothing runs at idle.
@MainActor
@Observable
final class UsageModel {
    enum Period: CaseIterable, Hashable {
        case thisMonth
        case last30Days

        var title: String {
            switch self {
            case .thisMonth: "This Month"
            case .last30Days: "Last 30 Days"
            }
        }

        func start(at now: Date) -> Date {
            switch self {
            case .thisMonth: Calendar.current.dateInterval(of: .month, for: now)?.start ?? now
            case .last30Days: Calendar.current.date(byAdding: .day, value: -30, to: now) ?? now
            }
        }
    }

    var period = Period.thisMonth
    private(set) var summaries: [Period: UsageSummary] = [:]
    private(set) var isLoadFailed = false
    /// Each top app's name and icon by bundle ID, read once per load, not at each draw.
    private(set) var names: [String: String] = [:]
    private(set) var icons: [String: NSImage] = [:]

    /// The answers from `start` on. Nil for snapshots, which set the summaries themselves.
    @ObservationIgnored private let read: (@MainActor (_ start: Date) async throws -> UsageSummary)?
    /// The read in progress; a history write during it asks for one more read after it, so a burst of writes costs
    /// at most two reads.
    @ObservationIgnored private var reading: Task<Void, Never>?
    @ObservationIgnored private var isReadDue = false
    @ObservationIgnored private var isShown = false

    init(read: @escaping @MainActor (_ start: Date) async throws -> UsageSummary) {
        self.read = read
    }

    /// For snapshots: fixed summaries and no store.
    init(summaries: [Period: UsageSummary]) {
        read = nil
        self.summaries = summaries
        readApps()
    }

    var summary: UsageSummary? { summaries[period] }

    /// The pane appeared, or the owner asked to try again.
    func show() {
        isShown = true
        reload()
    }

    func hide() {
        isShown = false
        reading?.cancel()
        reading = nil
    }

    /// A dictation was saved or deleted: a shown pane reads again; a hidden one reads when it appears.
    func historyChanged() {
        guard isShown else { return }
        reload()
    }

    private func reload() {
        guard read != nil else { return }
        guard reading == nil else {
            isReadDue = true
            return
        }
        reading = Task {
            repeat {
                isReadDue = false
                await load()
            } while isReadDue && !Task.isCancelled
            // A cancelled read was already replaced by `hide()`, maybe by a newer one: leave that handle alone.
            if !Task.isCancelled { reading = nil }
        }
    }

    private func load() async {
        guard let read else { return }
        let now = Date.now
        var loaded: [Period: UsageSummary] = [:]
        do {
            for period in Period.allCases {
                loaded[period] = try await read(period.start(at: now))
            }
        } catch {
            guard !Task.isCancelled else { return }
            Log.app.error("Cannot read usage: \(error)")
            isLoadFailed = true
            return
        }
        // `hide()` cancelled it; a newer read may already be running.
        guard !Task.isCancelled else { return }
        isLoadFailed = false
        summaries = loaded
        readApps()
    }

    /// A row keeps the app's name from its newest dictation; an app kept without one gets its installed name.
    private func readApps() {
        var names: [String: String] = [:]
        var icons: [String: NSImage] = [:]
        for app in summaries.values.flatMap(\.apps).map(\.app) where names[app.bundleID] == nil {
            names[app.bundleID] = app.name ?? InstalledApp.name(of: app.bundleID) ?? "Unknown app"
            icons[app.bundleID] = InstalledApp.icon(of: app.bundleID)
        }
        self.names = names
        self.icons = icons
    }
}

private struct UsagePane: View {
    @Bindable var model: UsageModel

    var body: some View {
        Form {
            Section {
                PaneHeader(pane: .usage)
            }
            Section {
            } header: {
                // Centered above the numbers, as the period switch in System Settings > Battery.
                Picker("Period", selection: $model.period) {
                    ForEach(UsageModel.Period.allCases, id: \.self) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .fixedSize()
                .frame(maxWidth: .infinity)
            }
            if model.isLoadFailed {
                Section {
                    LabeledContent {
                        Button("Try Again", action: model.show)
                    } label: {
                        Text("Couldn’t read your dictation history.")
                    }
                }
            } else if let summary = model.summary {
                if summary.dictations == 0 && summary.cost == 0 {
                    Section {
                        ContentUnavailableView(
                            Self.emptyTitle(model.period), systemImage: "chart.bar",
                            description: Text("Your words, audio and spend appear here after you dictate."))
                    }
                } else {
                    totals(summary)
                    models(summary)
                    apps(summary)
                }
            }
        }
        .formStyle(.grouped)
        .onAppear(perform: model.show)
        .onDisappear(perform: model.hide)
    }

    private func totals(_ summary: UsageSummary) -> some View {
        let amounts = DollarAmounts(summary)
        return Section {
            LabeledContent("Dictations", value: summary.dictations.formatted())
            LabeledContent("Words", value: summary.words.formatted())
            LabeledContent("Audio", value: Self.audio(summary.audio))
            LabeledContent {
                Text(amounts.total)
            } label: {
                Text("Spend")
                if let note = Self.spendNote(summary) {
                    Text(note)
                }
            }
        } footer: {
            Text(
                "Spend is the cost your provider reported. It stays when you delete dictations. When the provider "
                    + "reports none, kotoba estimates it from list prices.")
        }
    }

    @ViewBuilder
    private func models(_ summary: UsageSummary) -> some View {
        if !summary.models.isEmpty {
            let amounts = DollarAmounts(summary)
            Section("Spend by Model") {
                ForEach(summary.models) { spend in
                    LabeledContent {
                        Text(spend.cost == 0 && spend.unpricedAnswers > 0 ? "Unknown" : amounts.part(spend.id))
                    } label: {
                        Text(Self.title(of: spend))
                        Text(
                            [
                                spend.kind == .cleanup ? "Cleanup model" : "Speech model",
                                spend.isEstimated ? "Estimated" : nil,
                                spend.unpricedAnswers > 0 ? Self.unpricedNote(spend.unpricedAnswers) : nil,
                            ]
                            .compactMap(\.self).joined(separator: " · "))
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func apps(_ summary: UsageSummary) -> some View {
        if !summary.apps.isEmpty {
            Section("Top Apps") {
                ForEach(summary.apps, id: \.app.bundleID) { row in
                    LabeledContent {
                        Text(StatusText.counted(row.words, "word"))
                    } label: {
                        Label {
                            Text(model.names[row.app.bundleID] ?? "Unknown app")
                        } icon: {
                            if let icon = model.icons[row.app.bundleID] {
                                Image(nsImage: icon).resizable().frame(width: 20, height: 20)
                            } else {
                                Image(systemName: "app.dashed")
                            }
                        }
                    }
                }
            }
        }
    }

    private static func emptyTitle(_ period: UsageModel.Period) -> String {
        switch period {
        case .thisMonth: "No Dictations This Month"
        case .last30Days: "No Dictations in the Last 30 Days"
        }
    }

    /// The model's display name; a model kotoba no longer offers gets a generic one, never its identifier.
    private static func title(of spend: ModelSpend) -> String {
        switch spend.kind {
        case .cleanup:
            CleanupModel(rawValue: spend.model)?.title ?? "Earlier cleanup model"
        case .speech:
            TranscriptionRoute(rawValue: spend.model)?.menuTitle ?? "Earlier speech model"
        }
    }

    /// What the total leaves out or estimates; nil when it is exact.
    private static func spendNote(_ summary: UsageSummary) -> String? {
        var notes: [String] = []
        if summary.isCostEstimated {
            notes.append("Estimated in part from list prices")
        }
        if summary.unpricedAnswers > 0 {
            notes.append(unpricedNote(summary.unpricedAnswers))
        }
        return notes.isEmpty ? nil : notes.joined(separator: " · ")
    }

    /// Answers kept before kotoba recorded costs, or a rare answer with no cost and no token counts.
    private static func unpricedNote(_ count: Int) -> String {
        "Cost unknown for \(StatusText.counted(count, "request"))"
    }

    /// "42 sec" under a minute, else hours and minutes ("1 hr, 42 min").
    private static func audio(_ audio: Duration) -> String {
        audio < .seconds(60)
            ? audio.formatted(.units(allowed: [.seconds], width: .abbreviated))
            : audio.formatted(.units(allowed: [.hours, .minutes], width: .abbreviated))
    }
}

/// Dollar amounts as the pane shows them: up to four decimals under $1 (a dictation costs a fraction of a cent), else
/// cents.
/// The model rows are rounded so they add up to the rounded total: each is rounded down, and the units left go to
/// the rows that lost the most (largest remainder).
private struct DollarAmounts {
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

// MARK: - Snapshots

@MainActor
extension Pane {
    static func usageSnapshots() -> [Snapshot] {
        [
            MainWindow.snapshot(of: .usage(.sample), named: "settings-usage", height: 820),
            MainWindow.snapshot(of: .usage(.empty), named: "settings-usage-empty"),
        ]
    }
}

extension UsageModel {
    /// A month of synthetic use: a cleanup model, an estimated direct route, and four apps.
    static var sample: UsageModel {
        let month = UsageSummary(
            dictations: 412, words: 18_734, audio: .seconds(7_890), cost: Decimal(26_243) / 100_000,
            isCostEstimated: true, unpricedAnswers: 3,
            models: [
                .init(
                    .speech, model: TranscriptionRoute.openRouterMAI.rawValue, cost: Decimal(20_413) / 100_000,
                    unpricedAnswers: 3),
                .init(.cleanup, model: CleanupModel.geminiFlashLite.rawValue, cost: Decimal(4_786) / 100_000),
                .init(
                    .speech, model: TranscriptionRoute.xaiGrok.rawValue, cost: Decimal(1_044) / 100_000,
                    isEstimated: true),
            ],
            apps: [
                .init(app: DictationApp(bundleID: "com.apple.Terminal", name: "Terminal"), words: 9_120),
                .init(app: DictationApp(bundleID: "com.apple.mail", name: "Mail"), words: 4_388),
                .init(app: DictationApp(bundleID: "com.apple.Notes", name: "Notes"), words: 3_016),
                .init(app: DictationApp(bundleID: "com.apple.TextEdit", name: "TextEdit"), words: 2_210),
            ])
        return UsageModel(summaries: [.thisMonth: month, .last30Days: month])
    }

    /// No dictations in any period.
    static var empty: UsageModel {
        UsageModel(summaries: Dictionary(uniqueKeysWithValues: Period.allCases.map { ($0, UsageSummary()) }))
    }
}
