import Foundation
import KotobaCore
import KotobaStorage
import Observation
import SwiftUI

/// Story 31 in Settings > General: how long a transcribed dictation keeps its audio, the disk space the saved audio
/// takes, and "Delete Audio Now…". The pipeline decides what goes (`AudioRetention`); this model only passes the
/// owner's choices on as `AudioRequest`s. It measures the kept audio when the pane appears and after each history
/// write that changes it while it is shown, so nothing runs at idle.
@MainActor
@Observable
final class AudioRetentionModel {
    struct Source {
        /// Nil when a kept file cannot be measured.
        var size: @MainActor () async throws -> KeptAudioSize?
        /// The bytes a run with this cutoff would delete; nil when unknown.
        var expiring: @MainActor (Date) async throws -> Int64?
        var request: @MainActor (AudioRequest) -> Void
    }

    /// Changed through `choose(_:)`.
    private(set) var retention: AudioRetention
    /// A shorter period that would delete audio waits for the owner's confirmation, with the size it deletes (nil
    /// when it could not be measured), as Messages asks before it deletes older messages.
    var pendingRetention: (retention: AudioRetention, bytes: Int64?)?

    /// Nil until the first measure returns, or when it failed.
    private(set) var size: KeptAudioSize?
    var isAskingToDelete = false

    @ObservationIgnored private let source: Source
    /// The measure in progress; a history write during it asks for one more after it, as `UsageModel` reads.
    @ObservationIgnored private var measuring: Task<Void, Never>?
    @ObservationIgnored private var isMeasureDue = false
    @ObservationIgnored private var isShown = false
    /// Measures what a shorter period would delete; a newer choice cancels it.
    @ObservationIgnored private var checking: Task<Void, Never>?

    init(retention: AudioRetention, size: KeptAudioSize? = nil, source: Source) {
        self.retention = retention
        self.size = size
        self.source = source
    }

    /// The owner's setting, saved once confirmed; `requests` reaches the pipeline's one consumer (`AppDelegate`).
    static func live(requests: AsyncStream<AudioRequest>.Continuation, store: HistoryStore) -> AudioRetentionModel {
        AudioRetentionModel(
            retention: AppDefaults.audioRetention,
            source: Source(
                size: { try await store.keptAudioSize() },
                expiring: { try await store.expiringAudioBytes(transcribedBefore: $0) },
                request: { request in
                    if case .keep(let retention) = request {
                        AppDefaults.audioRetention = retention
                    }
                    requests.yield(request)
                }))
    }

    /// Fixed values for snapshots, with audio kept until sent: nothing is measured, saved or deleted.
    static func sample() -> AudioRetentionModel {
        let size = KeptAudioSize(deletable: 48_200_000, waiting: 2_100_000)
        return AudioRetentionModel(
            retention: .standard, size: size, source: Source(size: { size }, expiring: { _ in 0 }, request: { _ in }))
    }

    /// "Delete Audio Now…" has something to delete; on while the size is unknown, since the pipeline deletes only what
    /// it may.
    var hasDeletableAudio: Bool { size.map { $0.deletable > 0 } ?? true }

    /// The Picker's choice: a longer period, or a shorter one that deletes nothing, applies at once; a shorter one that
    /// would delete audio asks first, with the size. The Picker shows the old period until then.
    func choose(_ new: AudioRetention) {
        checking?.cancel()
        checking = nil
        guard new != retention else { return }
        guard new.keepsLess(than: retention), let cutoff = new.cutoff(at: .now) else { return apply(new) }
        checking = Task {
            var bytes: Int64?
            do {
                bytes = try await source.expiring(cutoff)
            } catch {
                // Unknown counts as something to delete: the owner is asked.
                Log.app.error("Cannot measure the audio a shorter period deletes: \(error)")
            }
            guard !Task.isCancelled else { return }
            checking = nil
            if bytes == 0 {
                apply(new)
            } else {
                pendingRetention = (new, bytes)
            }
        }
    }

    /// The owner confirmed the shorter period the dialog presented.
    func confirm(_ new: AudioRetention) {
        pendingRetention = nil
        apply(new)
    }

    private func apply(_ new: AudioRetention) {
        retention = new
        source.request(.keep(new))
    }

    func show() {
        isShown = true
        measure()
    }

    func hide() {
        isShown = false
        checking?.cancel()
        checking = nil
        measuring?.cancel()
        measuring = nil
    }

    /// A dictation was saved, or audio or a dictation was deleted (`HistoryChange.isKeptAudioChanged`): a shown pane
    /// measures again.
    func keptAudioChanged() {
        guard isShown else { return }
        measure()
    }

    func deleteNow() {
        source.request(.deleteNow)
    }

    private func measure() {
        guard measuring == nil else {
            isMeasureDue = true
            return
        }
        measuring = Task {
            repeat {
                isMeasureDue = false
                let measured: KeptAudioSize?
                do {
                    measured = try await source.size()
                } catch {
                    Log.app.error("Cannot measure the saved audio: \(error)")
                    break
                }
                guard !Task.isCancelled else { return }
                if size != measured { size = measured }
            } while isMeasureDue
            measuring = nil
        }
    }
}

/// The History section's asks of the pipeline, in click order.
enum AudioRequest: Sendable {
    case keep(AudioRetention)
    /// "Delete Audio Now…" (`DictationPipeline.deleteTranscribedAudio`).
    case deleteNow

    /// The one consumer: each request reaches the pipeline after the one before it.
    static func send(_ requests: AsyncStream<Self>, to pipeline: DictationPipeline) async {
        for await request in requests {
            switch request {
            case .keep(let retention): await pipeline.updateAudioRetention(retention)
            case .deleteNow: await pipeline.deleteTranscribedAudio()
            }
        }
    }
}

extension AudioRetention {
    var title: String {
        switch self {
        case .oneDay: "1 Day"
        case .sevenDays: "7 Days"
        case .thirtyDays: "30 Days"
        case .forever: "Forever"
        }
    }
}

/// The General pane's History section.
struct AudioSection: View {
    @Bindable var model: AudioRetentionModel

    var body: some View {
        Section {
            Picker("Keep audio", selection: Binding(get: { model.retention }, set: model.choose)) {
                ForEach(AudioRetention.allCases, id: \.self) { Text($0.title).tag($0) }
            }
            .confirmationDialog(
                "Delete Audio Older Than \(model.pendingRetention?.retention.title ?? "")?",
                isPresented: isAskingToShorten, presenting: model.pendingRetention
            ) { shorter in
                Button("Delete Audio", role: .destructive) { model.confirm(shorter.retention) }
            } message: { shorter in
                Text(Self.deleteMessage(bytes: shorter.bytes))
            }
            LabeledContent {
                Button("Delete Audio Now…") { model.isAskingToDelete = true }
                    .disabled(!model.hasDeletableAudio)
                    .confirmationDialog("Delete Saved Audio?", isPresented: $model.isAskingToDelete) {
                        Button("Delete Audio", role: .destructive, action: model.deleteNow)
                    } message: {
                        Text(Self.deleteMessage(bytes: model.size?.deletable))
                    }
            } label: {
                Text("Saved audio")
                if let size = model.size {
                    Text(size.deletable.formatted(.byteCount(style: .file)))
                }
            }
        } header: {
            Text("History")
        } footer: {
            if let waiting = model.size?.waiting, waiting > 0 {
                Text(
                    "History keeps the text of every dictation. Audio not yet transcribed "
                        + "(\(waiting.formatted(.byteCount(style: .file)))) stays until you retry or delete it.")
            } else {
                Text("History keeps the text of every dictation.")
            }
        }
        .onAppear(perform: model.show)
        .onDisappear(perform: model.hide)
    }

    /// Both questions: the size when it is known, then what stays.
    private static func deleteMessage(bytes: Int64?) -> String {
        let scope = "The text stays in History, and audio not yet transcribed stays for Retry. You can’t undo this."
        guard let bytes else { return scope }
        return "This deletes \(bytes.formatted(.byteCount(style: .file))) of audio. " + scope
    }

    /// Cancel or a click outside the dialog keeps the period as it was.
    private var isAskingToShorten: Binding<Bool> {
        Binding {
            model.pendingRetention != nil
        } set: {
            if !$0 { model.pendingRetention = nil }
        }
    }
}
