import KotobaCore
import KotobaProviders
import KotobaStorage

/// The History page (story 30): past dictations with Copy, Paste Again, Retry, Transcribe Again, Play and Delete, and
/// how long their audio stays (story 31). Its models are built with the main window and released when the window closes;
/// while the window is closed, history writes cost it nothing.
@MainActor
final class HistoryController {
    private let store: HistoryStore
    private let pipeline: DictationPipeline
    /// Opens the Fix window with a row's text.
    private let fix: @MainActor (DictationRecord) -> Void
    /// The speech model choice and the saved keys, for "Transcribe Again With".
    private let routes: TranscriptionSettings
    private let keys: KeyVault
    /// The Audio section's choices, to the pipeline's one consumer (`AudioRequest.send`).
    private let audioRequests: AsyncStream<AudioRequest>.Continuation
    private(set) var model: HistoryModel?
    /// The pipeline's newest activity, kept while the window is closed so it opens with it.
    private var activity = PipelineActivity(isQuiet: true, inFlight: [])
    /// History changes for the open window, applied one at a time in order (two saves of one dictation must not land
    /// out of order). Both end when the window closes.
    private var changes: AsyncStream<HistoryChange>.Continuation?
    private var applying: Task<Void, Never>?

    init(
        store: HistoryStore, pipeline: DictationPipeline, routes: TranscriptionSettings, keys: KeyVault,
        audioRequests: AsyncStream<AudioRequest>.Continuation, fix: @escaping @MainActor (DictationRecord) -> Void
    ) {
        self.store = store
        self.audioRequests = audioRequests
        self.pipeline = pipeline
        self.routes = routes
        self.keys = keys
        self.fix = fix
    }

    /// Every route but the current one whose key (and, for Azure, endpoint) is saved, in the Speech pane's order.
    private var otherSpeechModels: [MenuChoice] {
        let current = routes.route
        return TranscriptionRoute.allCases.filter {
            $0 != current && routes.missingSetup(for: $0, hasKey: keys.hasKey(for:)) == nil
        }.map { MenuChoice(title: $0.menuTitle, value: $0.rawValue) }
    }

    /// The page, with a new model that follows history writes until `windowClosed()`.
    func pane() -> Pane {
        let model = HistoryModel(source: source, audio: .live(requests: audioRequests, store: store))
        model.activity = activity
        self.model = model
        let (stream, continuation) = AsyncStream.makeStream(of: HistoryChange.self)
        changes = continuation
        applying = Task {
            for await change in stream {
                await model.apply(change)
            }
        }
        return .history(model)
    }

    func windowClosed() {
        // The model goes with the window; its audio must not play on with no Stop button.
        model?.playback.stop()
        changes?.finish()
        applying?.cancel()
        changes = nil
        applying = nil
        model = nil
    }

    /// A history write (from `DictationPipeline.historyChanges`): an open window reads the row it names, and the Audio
    /// section measures the kept audio again when the write changed it.
    func historyChanged(_ change: HistoryChange) {
        changes?.yield(change)
        if change.isKeptAudioChanged {
            model?.audio?.keptAudioChanged()
        }
    }

    /// From `DictationPipeline.activity`: which dictations are being sent, and whether Paste Again can paste.
    func activityChanged(_ activity: PipelineActivity) {
        self.activity = activity
        model?.activity = activity
    }

    private var source: HistoryModel.Source {
        let store = store
        let pipeline = pipeline
        return HistoryModel.Source(
            page: { try await store.page(matching: $0, after: $1, limit: $2) },
            record: { try await store.record($0, matching: $1) },
            delete: { await pipeline.delete($0) },
            retry: { await pipeline.retry($0) },
            paste: { await PasteAgain(pipeline: pipeline)($0, of: $1) },
            copy: { await pipeline.copyAgain($0) },
            transcribeAgain: { await pipeline.transcribeAgain($0, model: $1) },
            otherSpeechModels: { [weak self] in self?.otherSpeechModels ?? [] },
            fix: fix
        )
    }
}
