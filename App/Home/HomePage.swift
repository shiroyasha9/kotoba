import Charts
import KotobaCore
import KotobaStorage
import SwiftUI

extension Pane {
    static func home(_ model: HomeModel) -> Self {
        Pane(id: .home) {
            AnyView(HomePage(model: model))
        }
    }
}

/// The first page of the main window (docs/research/ui-redesign.md, "Page map"): today's words, or the setup problem and
/// its fix; the two ways to dictate; the last dictation with what can be done with it; the 4 before it. No header card:
/// the sidebar's name and the today card do that job.
private struct HomePage: View {
    @Bindable var model: HomeModel
    @Environment(\.openPane) private var openPane

    /// The rows under the last dictation.
    private static let earlierCount = HomeModel.recentCount - 1

    var body: some View {
        PageForm {
            if let missing = model.readiness.firstMissing {
                Section {
                    problem(missing)
                }
            } else if let insights = model.reader.value?.insights, insights.dictations > 0 {
                Section {
                    today(insights)
                }
            }
            Section {
                PageRow(title: StatusText.shortcutTitle(.handsFree), subtitle: StatusText.shortcutHelp(.handsFree)) {
                    Keycaps(keys: model.chords.handsFree.keycaps)
                }
                PageRow(title: StatusText.shortcutTitle(.pushToTalk), subtitle: StatusText.pushToTalkHelp(model.chords))
                {
                    Keycaps(keys: model.chords.pushToTalk.keycaps)
                }
            }
            if model.reader.isLoadFailed {
                Section {
                    LoadFailedRow(retry: model.reader.show)
                }
            } else if let figures = model.reader.value {
                if let last = figures.recent.first {
                    lastDictation(last, isFixable: last.id == figures.lastDelivered)
                    earlier(Array(figures.recent.dropFirst().prefix(Self.earlierCount)), retryable: figures.retryable)
                } else {
                    Section {
                        PageRow(title: "No dictations yet", subtitle: StatusText.howToDictate(model.chords) + ".") {
                            // Only once kotoba can dictate: before, the fix above comes first.
                            if model.readiness.firstMissing == nil {
                                Button("Try It…", action: model.tryIt)
                            }
                        }
                    }
                }
            }
        }
        .reads(through: model.reader)
        .onAppear(perform: model.readiness.refresh)
        .pasteFailureAlert(isPresented: $model.isPasteFailureShown)
    }

    /// Setup is not complete: the problem and the button that fixes it take the today card's place. The fix goes the
    /// way of the menu's “Finish Setting Up kotoba…” (`SetupFlow.finishSetup`).
    private func problem(_ missing: Readiness.Missing) -> some View {
        PageRow(title: "Not ready to dictate", subtitle: missing.problemText) {
            SymbolTile(systemImage: "exclamationmark.triangle", tint: .orange, side: PageMetrics.rowTileSide)
        } trailing: {
            Button(Self.fixTitle(missing), action: model.finishSetup)
                .buttonStyle(.borderedProminent)
        }
    }

    /// Today as Screen Time's "Daily Average" card: the words as the headline, the time they saved and the streak
    /// under it, and the week's bars; it opens Activity. Custom: a button card, as System Settings' cards that open a
    /// page; `NavigationLink` needs a navigation stack, which the window's detail column does not have.
    private func today(_ insights: DictationInsights) -> some View {
        Button {
            openPane(.activity)
        } label: {
            HStack {
                ChartHeadline(
                    label: "Today", value: StatusText.counted(model.todayWords, "word"),
                    detail: Self.todaySummary(insights)
                )
                .fixedSize()
                WeekBars(days: ChartDays(insights.days, last: ChartDays.week))
                Image(systemName: "chevron.forward")
                    .foregroundStyle(.tertiary)
            }
            .fixedSize(horizontal: false, vertical: true)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityHint("Shows Activity")
    }

    /// "About 11m saved · 5-day streak"; a part with nothing to say is left out.
    private static func todaySummary(_ insights: DictationInsights) -> String {
        let saved = insights.savedToday
        return [
            saved >= .seconds(60) ? "About \(saved.pageText) saved" : nil,
            insights.streak > 0 ? "\(insights.streak.formatted())-day streak" : nil,
        ]
        .compactMap(\.self).joined(separator: " · ")
    }

    /// The last dictation in full, with what can be done with it. "Fix…" fixes the last dictation that reached the
    /// owner, so it is on only when this is that one.
    private func lastDictation(_ record: DictationRecord, isFixable: Bool) -> some View {
        Section("Last Dictation") {
            VStack(alignment: .leading) {
                PageRow(
                    title: record.app.flatMap(model.apps.name(of:)) ?? "Unknown app", subtitle: Self.details(of: record)
                ) {
                    AppIconView(icon: model.apps.icon(of: record.app))
                } trailing: {
                    time(of: record)
                        .foregroundStyle(.secondary)
                }
                VStack(alignment: .leading) {
                    if record.hasText, let text = record.latestText {
                        Text(text)
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    } else {
                        Text(status(of: record)?.title ?? "No text")
                            .foregroundStyle(.secondary)
                    }
                    HStack {
                        Button("Fix…", action: model.fixLast)
                            .disabled(!isFixable)
                        Spacer()
                        Button("Copy") { model.copy(record) }
                            .disabled(!record.hasText)
                        Button("Paste Again") { model.pasteAgain(record) }
                            .disabled(!model.canPasteAgain(record))
                    }
                }
                .inRowTextColumn()
            }
        }
    }

    /// The dictations before the last, one line each: the text, or what happened to it in History's words.
    private func earlier(_ records: [DictationRecord], retryable: Set<DictationID>) -> some View {
        Section {
            ForEach(records) { record in
                LabeledContent {
                    time(of: record)
                } label: {
                    // The page's one icon column, as the Last Dictation card above (Screen Time's one-line rows use the
                    // same tile as its two-line rows).
                    RowLeading {
                        AppIconView(icon: model.apps.icon(of: record.app))
                    } content: {
                        if record.hasText, let text = record.latestText {
                            Text(text).lineLimit(1)
                        } else {
                            Text(status(of: record)?.title ?? "No text")
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                    }
                }
            }
        } header: {
            HStack {
                Text("Earlier")
                Spacer()
                Button("Show All") { openPane(.history) }
                    .buttonStyle(.link)
            }
        }
    }

    /// What happened to a dictation with no text ("Waiting for retry", "Canceled"), in History's words.
    private func status(of record: DictationRecord) -> HistoryStatus? {
        HistoryStatus(
            record, isSending: model.activity.inFlight.contains(record.id),
            isTranscribingAgain: model.activity.transcribingAgain.contains(record.id))
    }

    /// The dictation's time, after a warning when the owner should act (a retry, a silent mic), as History marks it.
    private func time(of record: DictationRecord) -> some View {
        HStack {
            if let status = status(of: record), status.isProblem {
                Image(systemName: status.systemImage)
                    .foregroundStyle(.orange)
                    .accessibilityLabel(status.title)
            }
            Text(record.createdAt.formatted(date: .omitted, time: .shortened))
                .monospacedDigit()
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

/// The week's words as Screen Time's week: Activity's bars (`DayBars`) with today in the brand colour, the day
/// initials under them, no word counts; it takes the height of the headline beside it.
private struct WeekBars: View {
    let days: ChartDays

    var body: some View {
        Chart {
            DayBars(days: days, marksToday: true)
        }
        .chartYScale(domain: 0...days.top)
        .chartXAxis {
            AxisMarks(values: .stride(by: .day)) { value in
                // Every slot keeps its mark, so Charts centres each label on its day; a blank slot's label is empty.
                AxisValueLabel(centered: true, anchor: .top) {
                    if let date = value.as(Date.self), days.isLabelled(date) {
                        Text(date, format: .dateTime.weekday(.narrow))
                    }
                }
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
