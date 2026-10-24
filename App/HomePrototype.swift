import AppKit
import Charts
import KotobaCore
import KotobaStorage
import SwiftUI

// The 0.5.0 Home page, as a prototype on the new visual system (`Page.swift`; docs/research/ui-redesign.md, "Page
// map"). It draws sample data only; the prototype goes when Home is rebuilt on it.

/// What the Home prototype shows: the samples the Home snapshots use.
@MainActor
struct HomePrototypeData {
    var readiness: Readiness
    var chords: HotkeyChords
    var appIcon: NSImage
    /// Newest first: the last dictation, then the ones before it.
    var recent: [DictationRecord]
    /// Words per day, today last, the streak and the speaking speed: the Activity sample, so both pages agree.
    var insights: DictationInsights
    let apps = InstalledApps()

    /// Home's snapshot sample: ready, five dictations, the Activity sample's days and streak.
    static var sample: Self { Self(HomeModel.sample, insights: ActivityPrototypeData.sample.insights) }

    /// A first launch: no OpenRouter key yet, nothing dictated.
    static var sampleNew: Self { Self(HomeModel.sampleNew, insights: DictationInsights()) }

    private init(_ model: HomeModel, insights: DictationInsights) {
        readiness = model.readiness
        chords = model.chords
        appIcon = model.identity.icon
        recent = model.reader.value?.recent ?? []
        self.insights = insights
    }

    var todayWords: Int { insights.days.last?.words ?? 0 }
}

struct HomePrototype: View {
    let data: HomePrototypeData
    /// Opens another page of the window: "Show All", the activity line.
    let open: (PrototypePage) -> Void

    /// The rows under the last dictation.
    private static let earlierCount = 4

    var body: some View {
        PageForm {
            if let missing = data.readiness.firstMissing {
                Section {
                    problem(missing)
                }
            } else if data.insights.dictations > 0 {
                Section {
                    today
                }
            }
            Section {
                shortcut(
                    "Hands-free", help: "Press to start, press again to stop.", keys: data.chords.handsFree.keycaps)
                shortcut("Push to talk", help: "Hold while you speak.", keys: data.chords.pushToTalk.keycaps)
            }
            if let last = data.recent.first {
                lastDictation(last)
                earlier(Array(data.recent.dropFirst().prefix(Self.earlierCount)))
            } else {
                // One row in the form's own type, not a pane-sized empty view in a card (review-window.md, 8).
                Section {
                    LabeledContent {
                        Button("Try It…") {}
                    } label: {
                        Text("No dictations yet")
                        Text("Press \(data.chords.handsFree.title) to start, press it again to stop.")
                    }
                }
            }
        }
    }

    /// Setup is not complete: the problem and the button that fixes it take the today card's place.
    private func problem(_ missing: Readiness.Missing) -> some View {
        LabeledContent {
            Button(Self.fixTitle(missing)) {}
                .buttonStyle(.borderedProminent)
        } label: {
            PageHeader(title: "Not ready to dictate", summary: missing.problemText) {
                SymbolTile(systemImage: "exclamationmark.triangle", tint: .orange, side: PageMetrics.headerTileSide)
            }
        }
    }

    /// Today as Screen Time's "Daily Average" card: the words as the headline, the time they saved and the streak
    /// under it, and the week's bars; it opens Activity. Custom: a button card, as System Settings' cards that open a
    /// page; `NavigationLink` needs a navigation stack, which the window's detail column does not have.
    private var today: some View {
        Button {
            open(.activity)
        } label: {
            HStack {
                ChartHeadline(
                    label: "Today", value: StatusText.counted(data.todayWords, "word"),
                    detail: Self.todaySummary(data.insights)
                )
                .fixedSize()
                WeekBars(days: DailyWords.shown(data.insights.days, period: .week))
                Image(systemName: "chevron.forward")
                    .foregroundStyle(.tertiary)
            }
            .fixedSize(horizontal: false, vertical: true)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
    }

    /// "About 11 min saved · 5-day streak": today's words typed at `InsightsModel.typingSpeed` less the time to say
    /// them at the owner's speaking speed, as Activity's "Time saved"; a part with nothing to say is left out.
    private static func todaySummary(_ insights: DictationInsights) -> String {
        let words = Double(insights.days.last?.words ?? 0)
        let typing = words / Double(InsightsModel.typingSpeed)
        let speaking = insights.wordsPerMinute.map { words / Double($0) } ?? 0
        let saved = Duration.seconds(Int(((typing - speaking) * 60).rounded()))
        return [
            saved >= .seconds(60)
                ? "About \(saved.formatted(.units(allowed: [.hours, .minutes], width: .abbreviated))) saved" : nil,
            insights.streak > 0 ? "\(insights.streak.formatted())-day streak" : nil,
        ]
        .compactMap(\.self).joined(separator: " · ")
    }

    private func shortcut(_ title: String, help: String, keys: [String]) -> some View {
        LabeledContent {
            Keycaps(keys: keys)
        } label: {
            Text(title)
            Text(help)
        }
    }

    /// The last dictation in full, with what can be done with it.
    private func lastDictation(_ record: DictationRecord) -> some View {
        Section("Last Dictation") {
            VStack(alignment: .leading) {
                LabeledContent {
                    Text(record.createdAt.formatted(date: .omitted, time: .shortened))
                        .monospacedDigit()
                } label: {
                    TileLabel(
                        title: record.app.flatMap(data.apps.name(of:)) ?? "Unknown app",
                        subtitle: Self.details(of: record)
                    ) {
                        AppIconView(icon: data.apps.icon(of: record.app), side: PageMetrics.rowTileSide)
                    }
                }
                // The text and its buttons start in the text column, under the app's name, as in System Settings'
                // rows with an icon.
                VStack(alignment: .leading) {
                    if let text = record.latestText, record.hasText {
                        Text(text)
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    HStack {
                        Button("Fix…") {}
                        Spacer()
                        Button("Copy") {}
                        Button("Paste Again") {}
                    }
                    .disabled(!record.hasText)
                }
                .padding(.leading, RowLeading<EmptyView, EmptyView>.textInset)
            }
        }
    }

    /// The dictations before the last, one line each.
    private func earlier(_ records: [DictationRecord]) -> some View {
        Section {
            ForEach(records) { record in
                let status = HistoryStatus(record, isSending: false, isTranscribingAgain: false)
                LabeledContent {
                    HStack {
                        if let status, status.isProblem {
                            Image(systemName: status.systemImage)
                                .foregroundStyle(.orange)
                                .accessibilityHidden(true)
                        }
                        Text(record.createdAt.formatted(date: .omitted, time: .shortened))
                            .monospacedDigit()
                    }
                } label: {
                    // The page's one icon column, as the Last Dictation card above (Screen Time's one-line rows use the
                    // same tile as its two-line rows).
                    RowLeading {
                        AppIconView(icon: data.apps.icon(of: record.app), side: PageMetrics.rowTileSide)
                    } content: {
                        if record.hasText, let text = record.latestText {
                            Text(text).lineLimit(1)
                        } else {
                            // What happened ("Not transcribed", "Canceled"), as History says it.
                            Text(status?.title ?? "No text").foregroundStyle(.secondary)
                        }
                    }
                }
            }
        } header: {
            HStack {
                Text("Earlier")
                Spacer()
                Button("Show All") { open(.history) }
                    .buttonStyle(.link)
            }
        }
    }

    /// "0:07 · 15 words".
    private static func details(of record: DictationRecord) -> String {
        var parts = [record.audio.duration.formatted(.time(pattern: .minuteSecond))]
        if let words = record.wordCount, words > 0 {
            parts.append(StatusText.counted(words, "word"))
        }
        return parts.joined(separator: " · ")
    }

    private static func fixTitle(_ missing: Readiness.Missing) -> String {
        switch missing {
        case .microphone: "Allow Microphone…"
        case .accessibility: "Allow Accessibility…"
        case .setup(.key, _): "Add Key…"
        case .setup(.endpoint, _): "Add Endpoint…"
        case .setup(.credit, _): "Add Credit…"
        }
    }
}

/// The week's words as Screen Time's week: Activity's bars (`DayBars`) with today in the accent colour, the day
/// initials under them, no word counts; it takes the height of the headline beside it.
private struct WeekBars: View {
    let days: [DictationInsights.Day]

    var body: some View {
        Chart {
            DayBars(days: days, marksToday: true)
        }
        .chartYScale(domain: 0...DailyWords.scaleTop(days.map(\.words).max() ?? 0))
        .chartXAxis {
            AxisMarks(values: .stride(by: .day)) {
                AxisValueLabel(format: .dateTime.weekday(.narrow), centered: true, anchor: .top)
            }
        }
        .chartYAxis(.hidden)
        // Headroom over the tallest bar: the system's padding, so the bars stay level with the figure, not the label.
        .padding(.top)
        // No height of its own: it takes the height of the text beside it.
        .frame(maxWidth: .infinity, minHeight: 0, idealHeight: 0, maxHeight: .infinity)
        .accessibilityLabel("Words per day this week")
    }
}
