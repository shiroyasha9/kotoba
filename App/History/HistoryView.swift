import AppKit
import KotobaCore
import SwiftUI

/// The History window's content: dictations by day, newest first, with search, a toolbar and a context menu.
struct HistoryView: View {
    @Bindable var model: HistoryModel
    @FocusState private var isSearchFocused: Bool

    var body: some View {
        content
            .frame(minWidth: 480, minHeight: 360)
            .searchable(text: $model.search, placement: .toolbar, prompt: "Search")
            .searchFocused($isSearchFocused)
            .onChange(of: model.findRequests) { isSearchFocused = true }
            .toolbar { toolbar(for: model.selected) }
            .task(id: model.search) { await model.reload() }
            .alert("Couldn’t Paste", isPresented: $model.isPasteFailureShown) {
                Button("OK") {}
            } message: {
                Text("kotoba couldn’t bring back the app you were in. The text is on the clipboard: press ⌘V there.")
            }
            .confirmationDialog(
                deleteTitle, isPresented: isAskingToDelete, presenting: model.pendingDelete
            ) { ids in
                Button("Delete", role: .destructive) { model.delete(ids) }
            } message: { _ in
                Text("The audio is deleted too. You can’t undo this.")
            }
    }

    @ViewBuilder private var content: some View {
        if let error = model.loadError {
            ContentUnavailableView(
                "History Unavailable", systemImage: "exclamationmark.triangle", description: Text(error))
        } else if model.rows.isEmpty, model.isLoaded {
            if model.search.isEmpty {
                ContentUnavailableView(
                    "No Dictations Yet", systemImage: "waveform",
                    description: Text("Tap \(StatusText.dictationChord) to dictate. Each dictation appears here."))
            } else {
                ContentUnavailableView.search(text: model.search)
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
                            record: record, icon: model.icon(for: record.app),
                            isRetryable: model.retryable.contains(record.id),
                            isSending: model.activity.inFlight.contains(record.id))
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
            Button("Retry", systemImage: "arrow.clockwise") { model.retry(records) }
                .help("Transcribe the saved audio again")
                .disabled(!model.canRetry(records))
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
            Divider()
            Button("Delete…", role: .destructive) { model.askToDelete(records) }
                .disabled(!model.canDelete(records))
        }
    }

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
    let icon: NSImage?
    /// No text yet, and the audio is kept for a retry.
    var isRetryable = false
    var isSending = false

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Group {
                if let icon {
                    Image(nsImage: icon).resizable()
                } else {
                    Color.clear
                }
            }
            .frame(width: 24, height: 24)
            .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                if let text = record.deliveredText, !text.isEmpty {
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
                Text(record.createdAt.formatted(date: .omitted, time: .shortened))
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                if let status = HistoryStatus(record, isSending: isSending) {
                    Label(status.title, systemImage: status.systemImage)
                        .foregroundStyle(status.isProblem ? AnyShapeStyle(.orange) : AnyShapeStyle(.secondary))
                }
            }
            .font(.subheadline)
        }
        .padding(.vertical, 4)
        .help(LastDictation.rawText(of: record).map { "Before cleanup: \($0)" } ?? "")
    }

    /// "Notes · 0:12 · 34 words": the app when known, the length, and the word count when there is text.
    private var details: String {
        var parts: [String] = []
        if let app = record.app, let name = app.name ?? InstalledApp.name(of: app.bundleID) {
            parts.append(name)
        }
        parts.append(record.audio.duration.formatted(.time(pattern: .minuteSecond)))
        let words = record.deliveredText.map(Self.wordCount) ?? 0
        if words > 0 {
            parts.append(StatusText.counted(words, "word"))
        }
        return parts.joined(separator: " · ")
    }

    /// Words are runs of non-space characters, counted without building them.
    private static func wordCount(_ text: String) -> Int {
        var count = 0
        var isInWord = false
        for character in text {
            if character.isWhitespace {
                isInWord = false
            } else if !isInWord {
                isInWord = true
                count += 1
            }
        }
        return count
    }
}

/// The note a row shows next to its details; a delivered dictation shows none.
struct HistoryStatus {
    let title: String
    let systemImage: String
    /// Asks the owner to act (Retry, or check the mic): drawn in orange.
    let isProblem: Bool

    init?(_ record: DictationRecord, isSending: Bool) {
        switch record.status {
        case .pasted, .copied:
            return nil
        case .recovered:
            (title, systemImage, isProblem) = ("Recovered", "checkmark.circle", false)
        case .cancelled:
            (title, systemImage, isProblem) = ("Cancelled", "xmark.circle", false)
        case .pending where isSending:
            (title, systemImage, isProblem) = ("Transcribing", "ellipsis.circle", false)
        case .pending, .failed:
            (title, systemImage, isProblem) = ("Not transcribed", "exclamationmark.triangle.fill", true)
        case .rejected where record.rejectReason == .emptyTranscript:
            (title, systemImage, isProblem) = ("No speech heard", "waveform.slash", true)
        case .rejected:
            (title, systemImage, isProblem) = ("Refused", "exclamationmark.triangle.fill", true)
        }
    }
}
