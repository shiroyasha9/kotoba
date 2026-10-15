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

    /// A history write (from `DictationPipeline.historyChanges`): an open window reads the row it names, and which
    /// dictations are in flight (two in flight change no state when one ends).
    func historyChanged(_ change: HistoryChange) {
        changes?.yield(change)
        readActivity()
    }

    /// A dictation started or ended: an open window reads which dictations are in flight.
    func dictationStateChanged() {
        readActivity()
    }

    private func readActivity() {
        guard let model else { return }
        Task { [pipeline] in
            model.isQuiet = await pipeline.isQuiet
            model.sending = await pipeline.inFlightIDs
        }
    }

    func windowWillClose(_ notification: Notification) {
        // A window that is still being freed keeps the name, and a new window with the same name would not save its
        // frame.
        window?.setFrameAutosaveName("")
        changes?.finish()
        applying?.cancel()
        changes = nil
        applying = nil
        window = nil
        model = nil
    }

    private func makeWindow() -> NSWindow {
        let model = HistoryModel(source: source)
        self.model = model
        readActivity()
        let (stream, continuation) = AsyncStream.makeStream(of: HistoryChange.self)
        changes = continuation
        applying = Task {
            for await change in stream {
                await model.apply(change)
            }
        }
        let window = Self.window(showing: model)
        window.delegate = self
        // The size and place the owner left it at; centred at the default size the first time.
        if !window.setFrameUsingName("History") {
            window.setContentSize(Self.defaultSize)
            window.center()
        }
        window.setFrameAutosaveName("History")
        return window
    }

    /// The window and its content, toolbar included; the snapshot run draws the same window.
    static func window(showing model: HistoryModel) -> NSWindow {
        let controller = NSHostingController(rootView: HistoryView(model: model))
        controller.sceneBridgingOptions = [.toolbars]
        let window = NSWindow(contentViewController: controller)
        window.title = "History"
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView]
        window.isReleasedWhenClosed = false
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
                guard await pipeline.isQuiet, await Self.returnFocus() else { return }
                await pipeline.pasteAgain(text, of: id)
            },
            copy: { await pipeline.copyAgain($0) }
        )
    }

    /// kotoba is the active app while this window is key, so a Cmd-V would land in it. The last app the owner was in
    /// comes back to the front (kotoba's windows stay as they are), and the paste waits for its activation, at most
    /// `focusWait`. False when there is no such app: the paste would land in kotoba.
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
                return
            }
        }
        let bound = Task {
            try? await Task.sleep(for: focusWait)  // Cancelled once the switch came: nothing to do.
            wait.cancel()
        }
        await wait.value
        bound.cancel()
        return true
    }
}
