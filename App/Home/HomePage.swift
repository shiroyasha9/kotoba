import KotobaCore
import KotobaProviders
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
            switch model.readiness.firstMissing {
            case .setup(.credit, let account):
                Section {
                    outOfCredit(account)
                }
            case let missing?:
                Section {
                    problem(missing)
                }
            case nil:
                if let insights = model.reader.value?.insights, insights.dictations > 0 {
                    Section {
                        today(insights)
                    }
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
                        // The chords are on the rows above, so the text does not spell them again (qa1-review).
                        EmptyRow(
                            title: StatusText.noDictationsTitle, systemImage: PaneID.history.systemImage,
                            description: "Dictate in any app, and your words show up here."
                        ) {
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

    /// The account is out of credit. The shortcut still records, and each dictation waits for credit, so the card is no
    /// "Not ready" line: it says so, with the fix and, once credit is back, the saved dictations' send, under the text
    /// as the Last Dictation card's actions.
    private func outOfCredit(_ account: ProviderAccount) -> some View {
        VStack(alignment: .leading) {
            PageRow(
                title: StatusText.outOfCredit(account),
                subtitle: "kotoba saves your dictations until you add credit."
            ) {
                SymbolTile(systemImage: "exclamationmark.triangle", tint: .orange, side: PageMetrics.rowTileSide)
            } trailing: {
                EmptyView()
            }
            HStack {
                Spacer()
                if let waiting = model.reader.value?.waitingCount, waiting > 0 {
                    Button("Send \(StatusText.counted(waiting, "Saved Dictation"))", action: model.sendSaved)
                        .disabled(model.isSendingSaved)
                }
                Button(Self.fixTitle(.setup(.credit, account)), action: model.finishSetup)
                    .buttonStyle(.borderedProminent)
            }
            .inRowTextColumn()
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
                // On the label's line at the top, as Screen Time's card puts it beside "Daily Average".
                Image(systemName: "chevron.forward")
                    .foregroundStyle(.tertiary)
                    .frame(maxHeight: .infinity, alignment: .top)
            }
            .fixedSize(horizontal: false, vertical: true)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityHint("Shows Activity")
    }

    /// "11m saved · 5-day streak"; a part with nothing to say is left out.
    private static func todaySummary(_ insights: DictationInsights) -> String {
        let saved = insights.savedToday
        return [
            saved >= .seconds(60) ? "\(saved.pageText) saved" : nil,
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
                    actions(for: record, isFixable: isFixable)
                }
                .inRowTextColumn()
            }
        }
    }

    /// Only what can be done with this dictation, as System Settings shows a disabled control only where its action
    /// can come back (qa1-review 9): its text's actions (Paste Again waits while a dictation is sent), Retry when its
    /// audio waits for one (off while it is sent), or none.
    @ViewBuilder private func actions(for record: DictationRecord, isFixable: Bool) -> some View {
        if record.hasText {
            HStack {
                if isFixable {
                    Button("Fix…", action: model.fixLast)
                }
                Spacer()
                Button("Copy") { model.copy(record) }
                Button("Paste Again") { model.pasteAgain(record) }
                    .disabled(!model.canPasteAgain(record))
            }
        } else if model.reader.value?.retryable.contains(record.id) == true {
            HStack {
                Spacer()
                Button("Retry") { model.retry(record) }
                    .disabled(!model.canRetry(record))
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

    /// When the dictation was (the time today, the day before), after a warning when the owner should act (a retry, a
    /// silent mic), as History marks it. Home has no day titles, so a time alone would read as today's.
    private func time(of record: DictationRecord) -> some View {
        HStack {
            if let status = status(of: record), status.isProblem {
                Image(systemName: status.systemImage)
                    .foregroundStyle(.orange)
                    .accessibilityLabel(status.title)
            }
            Text(model.when(record))
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
