import AppKit
import KotobaCore
import KotobaProviders
import KotobaStorage

/// The History pane (story 30): past dictations with Copy, Paste Again, Retry, Transcribe Again, Play and Delete. Its
/// model is built with the main window and released when the window closes; while the window is closed, history
/// writes cost it nothing.
@MainActor
final class HistoryController {
    /// The longest Paste Again waits for the app the owner was in to come back to the front.
    private static let focusWait = Duration.milliseconds(500)

    private let store: HistoryStore
    private let pipeline: DictationPipeline
    /// Opens the Fix window with a row's text.
    private let fix: @MainActor (DictationRecord) -> Void
    /// The speech model choice and the saved keys, for "Transcribe Again With".
    private let routes: TranscriptionSettings
    private let keys: KeyVault
    private var model: HistoryModel?
    /// The pipeline's newest activity, kept while the window is closed so it opens with it.
    private var activity = PipelineActivity(isQuiet: true, inFlight: [])
    /// History changes for the open window, applied one at a time in order (two saves of one dictation must not land
    /// out of order). Both end when the window closes.
    private var changes: AsyncStream<HistoryChange>.Continuation?
    private var applying: Task<Void, Never>?

    init(
        store: HistoryStore, pipeline: DictationPipeline, routes: TranscriptionSettings, keys: KeyVault,
        fix: @escaping @MainActor (DictationRecord) -> Void
    ) {
        self.store = store
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

    /// The pane, with a new model that follows history writes until `windowClosed()`.
    func pane() -> Pane {
        let model = HistoryModel(source: source)
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
        changes?.finish()
        applying?.cancel()
        changes = nil
        applying = nil
        model = nil
    }

    /// A history write (from `DictationPipeline.historyChanges`): an open window reads the row it names.
    func historyChanged(_ change: HistoryChange) {
        changes?.yield(change)
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
            paste: { text, id in
                guard await pipeline.isQuiet else { return true }
                guard await Self.returnFocus() else {
                    // The paste would land in kotoba: the text waits on the clipboard instead.
                    await pipeline.copyAgain(text)
                    return false
                }
                await pipeline.pasteAgain(text, of: id)
                return true
            },
            copy: { await pipeline.copyAgain($0) },
            transcribeAgain: { await pipeline.transcribeAgain($0, model: $1) },
            otherSpeechModels: { [weak self] in self?.otherSpeechModels ?? [] },
            fix: fix
        )
    }

    /// kotoba is the active app while its window is key, so a Cmd-V would land in it. The last app the owner was in
    /// comes back to the front (kotoba's windows stay as they are), and the paste waits for its activation, at most
    /// `focusWait`. False when there is no such app or it did not come to the front in time: the paste would land in
    /// kotoba.
    private static func returnFocus() async -> Bool {
        guard NSApp.isActive else { return true }
        guard let id = FrontAppObserver.lastOtherProcessID, let app = NSRunningApplication(processIdentifier: id),
            !app.isTerminated
        else { return false }
        // The sequence observes from its creation, so the activation is not missed.
        let activations = NSWorkspace.shared.notificationCenter.notifications(
            named: NSWorkspace.didActivateApplicationNotification)
        NSApp.yieldActivation(to: app)
        _ = app.activate(from: .current, options: [])
        let wait = Task {
            for await note in activations
            where (note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication)?.processIdentifier == id
            {
                return true
            }
            return false
        }
        let bound = Task {
            try? await Task.sleep(for: focusWait)  // Cancelled once the switch came: nothing to do.
            wait.cancel()
        }
        let isActivated = await wait.value
        bound.cancel()
        return isActivated
    }
}
