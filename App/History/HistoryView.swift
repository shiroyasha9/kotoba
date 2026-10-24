import AppKit
import KotobaCore
import SwiftUI

extension Pane {
    static func history(_ model: HistoryModel) -> Self {
        Pane(id: .history) {
            AnyView(HistoryView(model: model))
        }
    }
}

/// The History page (docs/research/ui-redesign.md, "Page map"): how long audio stays, the search, and the dictations
/// by day, newest first, in a list as Apple's list apps draw one (Mail, Notes, Voice Memos): rows load as they scroll
/// into view, several can be selected, and the list keys work (arrows, Space plays, Delete, ⌘C). The actions are in
/// the rows' context menu, as in those apps; there is no toolbar.
struct HistoryView: View {
    @Bindable var model: HistoryModel

    var body: some View {
        PageList(selection: $model.selection) {
            Section {
                PageHeader(page: .history, summary: "Every dictation, newest first, to copy, paste again or fix.")
                    .listRowSeparator(.hidden)
            }
            .selectionDisabled()
            if let audio = model.audio {
                AudioSection(model: audio)
                    .selectionDisabled()
            }
            content
        }
        .contextMenu(forSelectionType: DictationID.self) { ids in
            menu(for: model.rows.filter { ids.contains($0.id) })
        }
        .onDeleteCommand { model.askToDelete(model.selected) }
        // Space plays and stops the selected row's audio, as Quick Look does in Finder.
        .onKeyPress(.space) {
            guard model.canPlay(model.selected) || model.isPlaying(model.selected) else { return .ignored }
            model.togglePlay(model.selected)
            return .handled
        }
        // ⌘C copies the selected rows' text while the list has the focus; in the search field it copies the field's.
        .copyable(HistoryModel.text(of: model.selected).map { [$0] } ?? [])
        .task(id: model.readKey) { await model.show() }
        .pasteFailureAlert(isPresented: $model.isPasteFailureShown)
        .alert("Couldn’t Transcribe Again", isPresented: $model.isTranscribeFailureShown) {
            Button("OK") {}
        } message: {
            Text(
                "The speech model didn’t answer, or heard no words. The text stays as it was, and the audio stays "
                    + "saved, so you can try again.")
        }
        .alert("Couldn’t Delete", isPresented: $model.isDeleteFailureShown) {
            Button("OK") {}
        } message: {
            Text("kotoba couldn’t delete some dictations, so they stay in History. Try again later.")
        }
        .sheet(item: $model.changesShown) { record in
            ChangesView(record: record)
        }
        .confirmationDialog(
            deleteTitle, isPresented: isAskingToDelete, presenting: model.pendingDelete
        ) { ids in
            Button("Delete", role: .destructive) { model.delete(ids) }
        } message: { _ in
            Text("This also deletes the audio. You can’t undo this.")
        }
    }

    /// The search heads the first group of rows, so it stays while a search finds nothing.
    @ViewBuilder private var content: some View {
        if model.isLoadFailed {
            Section {
                LoadFailedRow(retry: model.tryAgain)
            }
            .selectionDisabled()
        } else if model.rows.isEmpty, model.isLoaded {
            Section {
                if model.search.isEmpty {
                    PageRow(
                        title: "No dictations yet",
                        subtitle: "\(StatusText.howToDictate(.shared)). Each dictation appears here."
                    ) {}
                } else {
                    PageRow(
                        title: "No results for “\(model.search)”",
                        subtitle: "Check the spelling or try a new search."
                    ) {}
                }
            } header: {
                search
            }
            .selectionDisabled()
        } else {
            ForEach(model.days) { day in
                Section {
                    ForEach(day.rows) { record in
                        row(record)
                    }
                } header: {
                    // One view: a header of two loose views lost the list's header style.
                    VStack(alignment: .leading) {
                        if day.id == model.days.first?.id {
                            search
                        }
                        Text(day.title)
                    }
                }
            }
            if !model.isComplete {
                // The last row: when it scrolls into view, the next page loads.
                ProgressView()
                    .controlSize(.small)
                    .frame(maxWidth: .infinity)
                    .selectionDisabled()
                    // A new last row (a page came in, or a reload dropped one) loads again.
                    .task(id: model.rows.last?.id) { await model.loadMore() }
            }
        }
    }

    private var search: some View {
        PageSearchField(text: $model.search, prompt: "Search")
    }

    private func row(_ record: DictationRecord) -> some View {
        HistoryRow(
            record: record, apps: model.apps,
            isRetryable: model.retryable.contains(record.id),
            isSending: model.activity.inFlight.contains(record.id),
            isTranscribingAgain: model.transcribing.contains(record.id),
            isPlaying: model.isPlaying([record]))
    }

    /// The actions on the clicked rows (the selection when the click is in it): the text, the audio, the changes, then
    /// Delete. No menu on the empty part of the list: every item needs a row.
    @ViewBuilder
    private func menu(for records: [DictationRecord]) -> some View {
        if !records.isEmpty {
            Section {
                Button("Copy") { model.copy(records) }
                    .disabled(!HistoryModel.hasText(records))
                if records.contains(where: { LastDictation.rawText(of: $0) != nil }) {
                    Button("Copy Without Cleanup") { model.copy(records, raw: true) }
                }
                Button("Paste Again") { model.pasteAgain(records) }
                    .disabled(!model.canPasteAgain(records))
                if model.canFix(records) {
                    Button("Fix…") { model.fix(records) }
                }
            }
            Section {
                // A row with no text joins the retry queue; one row with text is transcribed again.
                if model.canRetry(records) {
                    Button("Retry") { model.retry(records) }
                } else if model.againRecord(records) != nil {
                    transcribeAgainItems(for: records)
                }
                if model.isPlaying(records) {
                    Button("Stop Audio") { model.togglePlay(records) }
                } else if model.audioRecord(records) != nil {
                    Button("Play Audio") { model.togglePlay(records) }
                        .disabled(!model.canPlay(records))
                }
                if model.canViewChanges(records) {
                    Button("View Changes…") { model.viewChanges(records) }
                }
                if model.audioRecord(records) != nil {
                    Button("Show Audio in Finder") { model.showInFinder(records) }
                }
            }
            Section {
                Button("Delete…", role: .destructive) { model.askToDelete(records) }
                    .disabled(!model.canDelete(records))
            }
        }
    }

    /// Transcribe Again with the current speech model, and with each other one that can send now.
    @ViewBuilder
    private func transcribeAgainItems(for records: [DictationRecord]) -> some View {
        let isEnabled = model.canTranscribeAgain(records)
        Button("Transcribe Again") { model.transcribeAgain(records) }
            .help(Self.transcribeAgainHelp)
            .disabled(!isEnabled)
        let others = model.otherSpeechModels
        if !others.isEmpty {
            Menu("Transcribe Again With") {
                ForEach(others, id: \.value) { choice in
                    Button(choice.title) { model.transcribeAgain(records, model: choice.value) }
                }
            }
            .disabled(!isEnabled)
        }
    }

    /// Transcribe Again keeps no copy of the old text: the audio is what can bring a text back.
    private static let transcribeAgainHelp =
        "Transcribe the saved audio again. The new text replaces this one; the audio stays saved, so you can do it "
        + "again at any time."

    private var deleteTitle: String {
        let count = model.pendingDelete?.count ?? 0
        return count == 1 ? "Delete This Dictation?" : "Delete \(StatusText.counted(count, "Dictation"))?"
    }

    private var isAskingToDelete: Binding<Bool> {
        Binding {
            model.pendingDelete != nil
        } set: {
            if !$0 { model.pendingDelete = nil }
        }
    }
}

/// One dictation: the app's icon in the page's icon column, the text with its details under it, and the time and what
/// happened to it.
struct HistoryRow: View {
    let record: DictationRecord
    let apps: InstalledApps
    /// No text yet, and the audio is kept for a retry.
    var isRetryable = false
    var isSending = false
    var isTranscribingAgain = false
    var isPlaying = false

    var body: some View {
        HStack(alignment: .top) {
            RowLeading {
                AppIconView(icon: apps.icon(of: record.app))
            } content: {
                VStack(alignment: .leading) {
                    if record.hasText, let text = record.latestText {
                        Text(text).lineLimit(3)
                    } else {
                        Text(isRetryable ? "No text · audio saved" : "No text").foregroundStyle(.secondary)
                    }
                    Text(details)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                // The separator starts under the text, past the icon column, as Mail's.
                .alignmentGuide(.listRowSeparatorLeading) { $0[.leading] }
            }
            Spacer()
            VStack(alignment: .trailing) {
                HStack {
                    if isPlaying {
                        Image(systemName: "speaker.wave.2.fill")
                            .foregroundStyle(.tint)
                            .accessibilityLabel("Playing")
                    }
                    Text(record.createdAt.formatted(date: .omitted, time: .shortened))
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
                if let status = HistoryStatus(record, isSending: isSending, isTranscribingAgain: isTranscribingAgain) {
                    Label(status.title, systemImage: status.systemImage)
                        .font(.subheadline)
                        .foregroundStyle(status.isProblem ? AnyShapeStyle(.orange) : AnyShapeStyle(.secondary))
                }
            }
        }
        .help(LastDictation.rawText(of: record).map { "Before cleanup: \($0)" } ?? "")
    }

    /// "Notes · 0:12 · 34 words · audio deleted": the app when known, the length, the word count when there is text, and
    /// whether audio retention deleted the audio.
    private var details: String {
        var parts: [String] = []
        if let app = record.app, let name = apps.name(of: app) {
            parts.append(name)
        }
        parts.append(record.audio.duration.formatted(.time(pattern: .minuteSecond)))
        let words = record.wordCount ?? 0
        if words > 0 {
            parts.append(StatusText.counted(words, "word"))
        }
        if record.isAudioDeleted {
            parts.append("audio deleted")
        }
        return parts.joined(separator: " · ")
    }
}

/// The note a row shows next to its details; a delivered dictation shows none.
struct HistoryStatus {
    let title: String
    let systemImage: String
    /// Asks the owner to act (Retry, or check the mic): drawn in orange.
    let isProblem: Bool

    /// `isTranscribingAgain`: History's Transcribe Again is sending a row that has its text. A live dictation's row is
    /// `isSending` only, so it never reads "Transcribing" once it has its text.
    init?(_ record: DictationRecord, isSending: Bool, isTranscribingAgain: Bool) {
        if isTranscribingAgain {
            (title, systemImage, isProblem) = ("Transcribing", "ellipsis.circle", false)
            return
        }
        switch record.status {
        case .pasted, .copied:
            guard record.polishedText != nil else { return nil }
            (title, systemImage, isProblem) = ("Rewritten", IndicatorPanel.polishSymbol, false)
        // Text the owner did not get at its stop: a retry's, or one that came while kotoba quit.
        case .recovered, .notPasted:
            (title, systemImage, isProblem) =
                record.status == .recovered
                ? ("Recovered", "checkmark.circle", false) : ("Not pasted", "tray.and.arrow.down", false)
        case .cancelled:
            (title, systemImage, isProblem) = ("Canceled", "xmark.circle", false)
        case .pending where isSending:
            (title, systemImage, isProblem) = ("Transcribing", "ellipsis.circle", false)
        case .pending, .failed:
            (title, systemImage, isProblem) = ("Not transcribed", "exclamationmark.triangle.fill", true)
        case .rejected where record.rejectReason == .emptyTranscript:
            (title, systemImage, isProblem) = ("No speech heard", "waveform.slash", true)
        case .rejected where record.rejectReason == .audioMissing:
            (title, systemImage, isProblem) = ("Audio missing", "questionmark.folder", true)
        case .rejected:
            (title, systemImage, isProblem) = ("Refused", "exclamationmark.triangle.fill", true)
        }
    }
}
