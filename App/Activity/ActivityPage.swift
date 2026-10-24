import KotobaCore
import KotobaStorage
import SwiftUI

/// How much the owner dictates, in which apps, and what it costs: the chart, the highlights, the top apps and this
/// month's spend (docs/research/ui-redesign.md, "Page map").
struct ActivityPage: View {
    @Bindable var model: ActivityModel

    var body: some View {
        PageForm {
            Section {
                PageHeader(page: .activity, summary: "How much you dictate, in which apps, and what it costs.")
            }
            if model.reader.isLoadFailed {
                Section {
                    LoadFailedRow(retry: model.reader.show)
                }
            } else if let figures = model.reader.value {
                if figures.insights.dictations == 0 && figures.month.cost == 0 {
                    Section {
                        PageRow(
                            title: "No dictations yet",
                            subtitle: "Your words per day, speaking speed and top apps appear here after you dictate."
                        ) {}
                    }
                } else {
                    chart(figures.insights)
                    highlights(figures)
                    topApps(figures.insights)
                    month(figures.month)
                }
            }
        }
        .reads(through: model.reader)
        .sheet(isPresented: $model.isAdvancedShown) {
            if let month = model.reader.value?.month {
                SpendByModel(month: month)
            }
        }
    }

    private func chart(_ insights: DictationInsights) -> some View {
        Section {
            DailyWordsChart(days: ChartDays(insights.days, last: model.period.dayCount), period: model.period)
        } header: {
            // Above the chart card, outside it, so the card holds no control (owner, 2026-10-24); Battery puts its
            // period switch at the top of its charts. Centred: a segmented control does not stretch.
            HStack {
                Spacer()
                Picker("Period", selection: $model.period) {
                    ForEach(ActivityPeriod.allCases, id: \.self) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .fixedSize()
                Spacer()
            }
        }
    }

    private func highlights(_ figures: ActivityModel.Figures) -> some View {
        let insights = figures.insights
        let learned = figures.learned.values.reduce(0, +)
        let sources = [(SuggestionCandidate.Origin.edit, "from your edits"), (.fix, "from Fix Last Dictation")]
        let learnedParts = sources.compactMap { origin, text in
            figures.learned[origin].flatMap { $0 > 0 ? "\($0.formatted()) \(text)" : nil }
        }
        return Section("Highlights") {
            highlight(
                "Words per minute", "speedometer", .blue, value: insights.wordsPerMinute?.formatted() ?? "None",
                detail: "Speaking speed, pauses included")
            highlight(
                "Streak", "flame", .orange, value: StatusText.counted(insights.streak, "day"),
                detail: insights.streakDetail)
            highlight(
                "Time saved", "stopwatch", .green,
                value: insights.timeSaved(typingSpeed: ActivityModel.typingSpeed).pageText,
                detail: "Compared with typing at \(ActivityModel.typingSpeed) words a minute")
            highlight(
                "Words learned", "text.badge.checkmark", .purple, value: learned.formatted(),
                detail: learned == 0
                    ? "kotoba learns a word when you correct a dictation" : learnedParts.joined(separator: " · "))
        }
    }

    /// A highlight: a tile, a title with one line under it, and the figure.
    private func highlight(_ title: String, _ symbol: String, _ tint: Color, value: String, detail: String) -> some View
    {
        PageRow(title: title, subtitle: detail) {
            SymbolTile(systemImage: symbol, tint: tint, side: PageMetrics.rowTileSide)
        } trailing: {
            Text(value)
                .monospacedDigit()
                .foregroundStyle(.secondary)
        }
    }

    /// Every dictation's words by app, most first: the app icons in the page's one icon column, as Home's.
    @ViewBuilder private func topApps(_ insights: DictationInsights) -> some View {
        if !insights.apps.isEmpty {
            Section("Top Apps") {
                ForEach(insights.apps, id: \.app.bundleID) { row in
                    PageRow(title: model.apps.name(of: row.app) ?? "Unknown app", subtitle: nil) {
                        AppIconView(icon: model.apps.icon(of: row.app))
                    } trailing: {
                        Text(StatusText.counted(row.words, "word"))
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    private func month(_ month: UsageSummary) -> some View {
        Section {
            // The facts stay on screen in the row (copy rules), not in a footer beside the button.
            PageRow(title: "Spend", subtitle: Self.spendDetail(month)) {
                Text(DollarAmounts(month).total)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
            LabeledContent("Dictations", value: month.dictations.formatted())
            LabeledContent("Audio", value: month.audio.pageText)
        } header: {
            Text("This Month")
        } footer: {
            // Alone at the trailing edge under the group, as Battery's "Options…".
            if !month.models.isEmpty {
                HStack {
                    Spacer()
                    Button("Advanced…") { model.isAdvancedShown = true }
                }
            }
        }
    }

    /// What the spend is, that it outlives deleted dictations (review-window.md T10), and what it leaves out or
    /// estimates.
    private static func spendDetail(_ month: UsageSummary) -> String {
        var parts = ["What your speech and cleanup services billed. Spend stays when you delete dictations."]
        if month.isCostEstimated {
            parts.append("Partly estimated from list prices.")
        }
        if month.unpricedAnswers > 0 {
            parts.append(SpendByModel.unpricedNote(month.unpricedAnswers) + ".")
        }
        return parts.joined(separator: " ")
    }
}
