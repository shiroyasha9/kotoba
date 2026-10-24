import AppKit
import KotobaCore
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
    var todayWords: Int
    var streak: Int
    let apps = InstalledApps()

    /// Home's snapshot sample: ready, five dictations, 640 words today, a 5-day streak.
    static var sample: Self { Self(HomeModel.sample) }

    /// A first launch: no OpenRouter key yet, nothing dictated.
    static var sampleNew: Self { Self(HomeModel.sampleNew) }

    private init(_ model: HomeModel) {
        readiness = model.readiness
        chords = model.chords
        appIcon = model.identity.icon
        recent = model.reader.value?.recent ?? []
        todayWords = model.today?.words ?? 0
        streak = model.reader.value?.insights.streak ?? 0
    }
}

struct HomePrototype: View {
    let data: HomePrototypeData
    /// Opens another page of the window: "Show All", the activity line.
    let open: (PrototypePage) -> Void

    /// The rows under the last dictation.
    private static let earlierCount = 4

    var body: some View {
        PageForm {
            Section {
                status
                shortcut(
                    "Hands-free", help: "Press to start, press again to stop.", keys: data.chords.handsFree.keycaps)
                shortcut("Push to talk", help: "Hold while you speak.", keys: data.chords.pushToTalk.keycaps)
            }
            if let last = data.recent.first {
                lastDictation(last)
                earlier(Array(data.recent.dropFirst().prefix(Self.earlierCount)))
            } else {
                Section {
                    EmptyState(
                        "No Dictations Yet", systemImage: "waveform",
                        description: "Press \(data.chords.handsFree.title) to start, press it again to stop. "
                            + "Each dictation appears here.")
                }
            }
            if data.todayWords > 0 || data.streak > 0 {
                Section {
                    activityLine
                }
            }
        }
    }

    /// Ready, or the first problem and the button that fixes it.
    @ViewBuilder private var status: some View {
        if let missing = data.readiness.firstMissing {
            LabeledContent {
                Button(Self.fixTitle(missing)) {}
                    .buttonStyle(.borderedProminent)
            } label: {
                PageHeader(title: "Not ready to dictate", summary: missing.problemText) {
                    SymbolTile(systemImage: "exclamationmark.triangle", tint: .orange, side: PageMetrics.rowTileSide)
                }
            }
        } else {
            PageHeader(title: "Ready to dictate", summary: "Works in any app where you can type.") {
                AppIconView(icon: data.appIcon, side: PageMetrics.rowTileSide)
            }
        }
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
                } label: {
                    Label {
                        Text(record.app.flatMap(data.apps.name(of:)) ?? "Unknown app")
                        Text(Self.details(of: record))
                    } icon: {
                        AppIconView(icon: data.apps.icon(of: record.app), side: PageMetrics.rowTileSide)
                    }
                }
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
        }
    }

    /// The dictations before the last, one line each.
    private func earlier(_ records: [DictationRecord]) -> some View {
        Section {
            ForEach(records) { record in
                LabeledContent {
                    HStack {
                        if let status = HistoryStatus(record, isSending: false, isTranscribingAgain: false),
                            status.isProblem
                        {
                            Image(systemName: status.systemImage)
                                .foregroundStyle(.orange)
                                .accessibilityLabel(status.title)
                        }
                        Text(record.createdAt.formatted(date: .omitted, time: .shortened))
                            .monospacedDigit()
                    }
                } label: {
                    Label {
                        if record.hasText, let text = record.latestText {
                            Text(text).lineLimit(1)
                        } else {
                            Text("No text").foregroundStyle(.secondary)
                        }
                    } icon: {
                        AppIconView(icon: data.apps.icon(of: record.app), side: PageMetrics.lineTileSide)
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

    /// Today's words and the streak; it opens Activity. Custom: a row button, as System Settings' rows that open a
    /// page; `NavigationLink` needs a navigation stack, which the window's detail column does not have.
    private var activityLine: some View {
        Button {
            open(.activity)
        } label: {
            LabeledContent {
                Image(systemName: "chevron.forward")
                    .foregroundStyle(.tertiary)
            } label: {
                Label {
                    Text(Self.activitySummary(words: data.todayWords, streak: data.streak))
                } icon: {
                    SymbolTile(
                        systemImage: PrototypePage.activity.systemImage, tint: PrototypePage.activity.tint,
                        side: PageMetrics.lineTileSide)
                }
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
    }

    /// "640 words today · 5-day streak"; a part with nothing to say is left out.
    private static func activitySummary(words: Int, streak: Int) -> String {
        [
            words > 0 ? "\(StatusText.counted(words, "word")) today" : nil,
            streak > 0 ? "\(streak.formatted())-day streak" : nil,
        ]
        .compactMap(\.self).joined(separator: " · ")
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
