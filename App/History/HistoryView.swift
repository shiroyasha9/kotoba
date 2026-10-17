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

/// The History pane: dictations by day, newest first, with search, a toolbar and a context menu.
struct HistoryView: View {
    @Bindable var model: HistoryModel
    @FocusState private var isSearchFocused: Bool
    @Environment(\.findRequests) private var findRequests

    var body: some View {
        content
            .frame(minWidth: 480, minHeight: 360)
            .searchable(text: $model.search, placement: .toolbar, prompt: "Search")
            .searchFocused($isSearchFocused)
            .onChange(of: findRequests) { isSearchFocused = true }
            .toolbar { toolbar(for: model.selected) }
            .task(id: model.readKey) { await model.show() }
            .alert("Couldn’t Paste", isPresented: $model.isPasteFailureShown) {
                Button("OK") {}
            } message: {
                Text("kotoba couldn’t bring back the app you were in. The text is on the clipboard: press ⌘V there.")
            }
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

    @ViewBuilder private var content: some View {
        if model.isLoadFailed {
            EmptyState.loadFailed(retry: model.tryAgain)
        } else if model.rows.isEmpty, model.isLoaded {
            if model.search.isEmpty {
                EmptyState.noDictations(chords: .shared)
            } else {
                NoSearchResults(search: model.search)
            }
        } else {
            list
        }
    }

    private var list: some View {
        List(selection: $model.selection) {
            ForEach(model.days) { day in
                Section(day.title) {
                    ForEach(day.rows) { record in
                        HistoryRow(
                            record: record, apps: model.apps,
                            isRetryable: model.retryable.contains(record.id),
                            isSending: model.activity.inFlight.contains(record.id),
                            isTranscribingAgain: model.transcribing.contains(record.id),
                            isPlaying: model.isPlaying([record]))
                    }
                }
            }
            if !model.isComplete {
                // The last row: when it scrolls into view, the next page loads.
                ProgressView()
                    .controlSize(.small)
                    .frame(maxWidth: .infinity)
                    // A new last row (a page came in, or a reload dropped one) loads again.
                    .task(id: model.rows.last?.id) { await model.loadMore() }
            }
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
    }

    @ToolbarContentBuilder
    private func toolbar(for records: [DictationRecord]) -> some ToolbarContent {
        ToolbarItemGroup(placement: .primaryAction) {
            Button("Copy", systemImage: "doc.on.doc") { model.copy(records) }
                .help("Copy the text")
                .disabled(!HistoryModel.hasText(records))
            // A clipboard, not a second "doc.on…" symbol: Copy and Paste Again must differ at a glance.
            Button("Paste Again", systemImage: "clipboard") { model.pasteAgain(records) }
                .help("Paste the text in the app you were in")
                .disabled(!model.canPasteAgain(records))
            // A row with no text joins the retry queue; one row with text is transcribed again.
            if model.againRecord(records) != nil, !model.canRetry(records) {
                Button("Transcribe Again", systemImage: "arrow.clockwise") { model.transcribeAgain(records) }
                    .help(Self.transcribeAgainHelp)
                    .disabled(!model.canTranscribeAgain(records))
            } else {
                Button("Retry", systemImage: "arrow.clockwise") { model.retry(records) }
                    .help("Transcribe the saved audio again")
                    .disabled(!model.canRetry(records))
            }
            if model.isPlaying(records) {
                Button("Stop", systemImage: "stop.fill") { model.togglePlay(records) }
                    .help("Stop the audio")
            } else {
                Button("Play", systemImage: "play.fill") { model.togglePlay(records) }
                    .help("Play the saved audio")
                    .disabled(!model.canPlay(records))
            }
            Button("Delete", systemImage: "trash") { model.askToDelete(records) }
                .help("Delete the dictation and its audio")
                .disabled(!model.canDelete(records))
        }
    }

    /// No menu on the empty part of the list: every item needs a row.
    @ViewBuilder
    private func menu(for records: [DictationRecord]) -> some View {
        if !records.isEmpty {
            Button("Copy") { model.copy(records) }
                .disabled(!HistoryModel.hasText(records))
            if records.contains(where: { LastDictation.rawText(of: $0) != nil }) {
                Button("Copy Without Cleanup") { model.copy(records, raw: true) }
            }
            Button("Paste Again") { model.pasteAgain(records) }
                .disabled(!model.canPasteAgain(records))
            if model.canRetry(records) {
                Button("Retry") { model.retry(records) }
            }
            if model.againRecord(records) != nil {
                transcribeAgainItems(for: records)
            }
            if model.isPlaying(records) {
                Button("Stop Audio") { model.togglePlay(records) }
            } else if model.audioRecord(records) != nil {
                Button("Play Audio") { model.togglePlay(records) }
                    .disabled(!model.canPlay(records))
            }
            if model.audioRecord(records) != nil {
                Button("Show Audio in Finder") { model.showInFinder(records) }
            }
            if model.canViewChanges(records) || model.canFix(records) {
                Divider()
            }
            if model.canViewChanges(records) {
                Button("View Changes…") { model.viewChanges(records) }
            }
            if model.canFix(records) {
                Button("Fix Dictation…") { model.fix(records) }
            }
            Divider()
            Button("Delete…", role: .destructive) { model.askToDelete(records) }
                .disabled(!model.canDelete(records))
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

/// One dictation: the app's icon, the text, and its details under it.
struct HistoryRow: View {
    let record: DictationRecord
    let apps: InstalledApps
    /// No text yet, and the audio is kept for a retry.
    var isRetryable = false
    var isSending = false
    var isTranscribingAgain = false
    var isPlaying = false

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Group {
                if let icon = apps.icon(of: record.app) {
                    Image(nsImage: icon).resizable()
                } else {
                    Color.clear
                }
            }
            .frame(width: 24, height: 24)
            .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
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
            // The separator starts under the text, past the icon, also when the status label is the row's last text.
            .alignmentGuide(.listRowSeparatorLeading) { $0[.leading] }
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 3) {
                HStack(spacing: 4) {
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
                        .foregroundStyle(status.isProblem ? AnyShapeStyle(.orange) : AnyShapeStyle(.secondary))
                }
            }
            .font(.subheadline)
        }
        .padding(.vertical, 4)
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
            (title, systemImage, isProblem) = ("Polished", IndicatorPanel.polishSymbol, false)
        case .recovered:
            (title, systemImage, isProblem) = ("Recovered", "checkmark.circle", false)
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
