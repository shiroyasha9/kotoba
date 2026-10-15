import AppKit
import KotobaCore
import KotobaStorage
import SwiftUI

/// The History window (story 30): past dictations with Copy, Paste Again, Retry and Delete. Built when it opens and
/// released when it closes; while it is closed, history writes cost it nothing.
@MainActor
final class HistoryController: NSObject, NSWindowDelegate {
    static let defaultSize = NSSize(width: 640, height: 560)
    /// The longest Paste Again waits for the app the owner was in to come back to the front.
    private static let focusWait = Duration.milliseconds(500)

    private let store: HistoryStore
    private let pipeline: DictationPipeline
    private var window: NSWindow?
    private var model: HistoryModel?
    private var isDictating = false
    /// History changes for the open window, applied one at a time in order (two saves of one dictation must not land
    /// out of order). Both end when the window closes.
    private var changes: AsyncStream<HistoryChange>.Continuation?
    private var applying: Task<Void, Never>?

    init(store: HistoryStore, pipeline: DictationPipeline) {
        self.store = store
        self.pipeline = pipeline
    }

    func show() {
        let window = window ?? makeWindow()
        self.window = window
        NSApp.activate()
        window.makeKeyAndOrderFront(nil)
    }

    /// A history write (from `DictationPipeline.historyChanges`): an open window reads the row it names.
    func historyChanged(_ change: HistoryChange) {
        changes?.yield(change)
    }

    func dictationStateChanged(_ state: DictationState) {
        isDictating =
            switch state {
            case .recording, .transcribing, .undoable: true
            default: false
            }
        model?.isDictating = isDictating
    }

    func windowWillClose(_ notification: Notification) {
        changes?.finish()
        applying?.cancel()
        changes = nil
        applying = nil
        window = nil
        model = nil
    }

    private func makeWindow() -> NSWindow {
        let model = HistoryModel(source: source)
        model.isDictating = isDictating
        self.model = model
        let (stream, continuation) = AsyncStream.makeStream(of: HistoryChange.self)
        changes = continuation
        applying = Task {
            for await change in stream {
                await model.apply(change)
            }
        }
        let controller = NSHostingController(rootView: HistoryView(model: model))
        controller.sceneBridgingOptions = [.toolbars]
        let window = NSWindow(contentViewController: controller)
        window.title = "History"
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView]
        window.isReleasedWhenClosed = false
        window.delegate = self
        // The size and place the owner left it at; centred at the default size the first time.
        if !window.setFrameUsingName("History") {
            window.setContentSize(Self.defaultSize)
            window.center()
        }
        window.setFrameAutosaveName("History")
        return window
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
                // The window's flag follows the indicator, which can show an outcome while another dictation is sent.
                guard await pipeline.isQuiet else { return }
                await Self.returnFocus()
                await pipeline.pasteAgain(text, of: id)
            },
            copy: { await pipeline.copyAgain($0) }
        )
    }

    /// kotoba is the active app while this window is key, so a Cmd-V would land in it. Hiding kotoba gives the focus
    /// back to the app the owner was in (the indicator panel does not hide); the paste waits until that app is
    /// active, at most `focusWait`.
    private static func returnFocus() async {
        guard NSApp.isActive else { return }
        // The sequence observes from its creation, so the activation that `hide` causes is not missed.
        let activations = NSWorkspace.shared.notificationCenter.notifications(
            named: NSWorkspace.didActivateApplicationNotification)
        NSApp.hide(nil)
        let wait = Task {
            for await _ in activations { return }
        }
        let bound = Task {
            try? await Task.sleep(for: focusWait)  // Cancelled once the switch came: nothing to do.
            wait.cancel()
        }
        await wait.value
        bound.cancel()
    }
}
