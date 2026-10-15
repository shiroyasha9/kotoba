import AppKit
import ApplicationServices
import Carbon
import KotobaCore
import Synchronization
import os

/// Opens the focused text field of the frontmost app for a readback session (docs/research/auto-learning.md,
/// "Readback (phase 2.6)"). It uses the Accessibility grant the paste already has, so it asks for nothing new. With
/// "Learn from my edits" off, `EditReadback` never asks, so no observer and no thread is ever made.
struct AXFieldWatcher: FieldWatcher {
    /// The front app, read on the main thread (no call to the app).
    struct FrontApp: Sendable {
        var pid: pid_t
        var bundleID: String?
        /// With the pid, tells a new process that reuses a pid from the one kotoba woke.
        var launchDate: Date?
    }

    func focusedField() async -> (any FocusedField)? {
        let front = await MainActor.run { () -> FrontApp? in
            guard let app = NSWorkspace.shared.frontmostApplication,
                app.processIdentifier != ProcessInfo.processInfo.processIdentifier
            else { return nil }
            return FrontApp(pid: app.processIdentifier, bundleID: app.bundleIdentifier, launchDate: app.launchDate)
        }
        guard let front else { return nil }
        return await AXFocusedField.open(front)
    }
}

/// The focused field as Accessibility shows it. Every AX call of a session and the observer's callbacks run on the
/// session's own thread (`SessionThread`), never on the main thread, so a hung app cannot stall kotoba's UI.
/// Notifications become `FieldEvent`s; `read(radius:)` reads a bounded range around the insertion point. The text
/// stays in memory and is never logged.
///
/// `@unchecked Sendable`: the AX objects and the observer are touched only on `thread`, through `thread.run`.
final class AXFocusedField: FocusedField, @unchecked Sendable {
    /// A slow app (a terminal with a long scrollback) blocks one call, on the session thread, for at most this long.
    private static let timeout: Float = 0.25
    /// Fields without a ranged read are read whole only up to this length (UTF-16 units).
    private static let maxWholeRead = 20_000
    /// Electron apps whose tree kotoba has woken, by pid and launch date; each process is asked once.
    private static let wokenApps = Mutex<Set<String>>([])

    let appBundleID: String?
    let events: AsyncStream<FieldEvent>
    private let continuation: AsyncStream<FieldEvent>.Continuation
    private let thread: SessionThread
    private let element: AXUIElement
    private let application: AXUIElement
    private var observer: AXObserver?
    private var activation: (any NSObjectProtocol)?
    /// False after the field refused a ranged read: later reads go straight to the whole value.
    private var supportsRangedRead = true

    private init(thread: SessionThread, element: AXUIElement, application: AXUIElement, appBundleID: String?) {
        self.thread = thread
        self.element = element
        self.application = application
        self.appBundleID = appBundleID
        (events, continuation) = AsyncStream.makeStream(of: FieldEvent.self)
    }

    /// The focused field of `pid` when it is readable text and not secure; nil otherwise, and the thread ends.
    static func open(_ app: AXFieldWatcher.FrontApp) async -> AXFocusedField? {
        let pid = app.pid
        let process = "\(pid) \(app.launchDate?.timeIntervalSince1970 ?? 0)"
        let thread = await SessionThread.start()
        let opened = await thread.run { () -> AXFocusedField? in
            let interval = KotobaCore.Log.signposter.beginInterval("readback open")
            defer { KotobaCore.Log.signposter.endInterval("readback open", interval) }
            guard AXIsProcessTrusted(), !IsSecureEventInputEnabled() else { return nil }
            let application = AXUIElementCreateApplication(pid)
            AXUIElementSetMessagingTimeout(application, timeout)
            var element = focusedText(of: application)
            // Electron builds its tree only for assistive apps that ask (electronjs.org, Accessibility). The tree
            // builds after the call returns, so the next paste into this app is the first one read.
            if element == nil, wokenApps.withLock({ $0.insert(process).inserted }) {
                AXUIElementSetAttributeValue(application, "AXManualAccessibility" as CFString, kCFBooleanTrue)
                element = focusedText(of: application)
            }
            guard let element else { return nil }
            let field = AXFocusedField(
                thread: thread, element: element, application: application, appBundleID: app.bundleID)
            return field.observe(pid: pid) ? field : nil
        }
        guard let opened, let field = opened else {
            thread.stop()
            return nil
        }
        return field
    }

    /// The focused element when it holds text with an insertion point and is not a secure field.
    private static func focusedText(of application: AXUIElement) -> AXUIElement? {
        guard let element = attribute(kAXFocusedUIElementAttribute, of: application, as: AXUIElementGetTypeID()) else {
            return nil
        }
        let focused = unsafeDowncast(element, to: AXUIElement.self)
        AXUIElementSetMessagingTimeout(focused, timeout)
        let subrole = attribute(kAXSubroleAttribute, of: focused, as: CFStringGetTypeID()) as? String
        guard subrole != kAXSecureTextFieldSubrole, characterCount(of: focused) != nil,
            selectedRange(of: focused) != nil
        else { return nil }
        return focused
    }

    /// Registers the notifications on the session thread's run loop. False when the field sends no change
    /// notifications.
    private func observe(pid: pid_t) -> Bool {
        var created: AXObserver?
        guard AXObserverCreate(pid, fieldCallback, &created) == .success, let observer = created else { return false }
        self.observer = observer
        let refcon = Unmanaged.passUnretained(self).toOpaque()
        guard AXObserverAddNotification(observer, element, kAXValueChangedNotification as CFString, refcon) == .success
        else {
            stopObserving()
            return false
        }
        AXObserverAddNotification(observer, element, kAXUIElementDestroyedNotification as CFString, refcon)
        AXObserverAddNotification(observer, application, kAXFocusedUIElementChangedNotification as CFString, refcon)
        CFRunLoopAddSource(CFRunLoopGetCurrent(), AXObserverGetRunLoopSource(observer), .defaultMode)
        // Posted on the main thread; the hand-off is one yield.
        activation = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: nil
        ) { [continuation] _ in
            continuation.yield(.left)
        }
        return true
    }

    /// On the session thread: the observer's callback.
    func received(_ notification: String, from sender: AXUIElement) {
        switch notification {
        case kAXValueChangedNotification:
            continuation.yield(.changed)
        case kAXFocusedUIElementChangedNotification where CFEqual(sender, element):
            break
        default:
            continuation.yield(.left)
        }
    }

    func read(radius: Int) async -> String? {
        await thread.run { self.readNow(radius: radius) }.flatMap(\.self)
    }

    func close() async {
        _ = await thread.run { self.stopObserving() }
        thread.stop()
    }

    private func readNow(radius: Int) -> String? {
        let interval = KotobaCore.Log.signposter.beginInterval("readback read")
        defer { KotobaCore.Log.signposter.endInterval("readback read", interval) }
        // Focus that moved to a password field turns Secure Input on.
        guard !IsSecureEventInputEnabled(), let count = Self.characterCount(of: element),
            let caret = Self.selectedRange(of: element)?.location
        else { return nil }
        let window = EditReadback.readRange(caret: caret, length: count, radius: radius)
        if supportsRangedRead {
            var range = CFRange(location: window.lowerBound, length: window.count)
            if let value = AXValueCreate(.cfRange, &range) {
                var text: CFTypeRef?
                let result = AXUIElementCopyParameterizedAttributeValue(
                    element, kAXStringForRangeParameterizedAttribute as CFString, value, &text)
                if result == .success, let text = text as? String {
                    return text
                }
            }
            supportsRangedRead = false
        }
        guard count <= Self.maxWholeRead, let whole = Self.attribute(kAXValueAttribute, of: element) as? String
        else { return nil }
        let utf16 = whole.utf16
        guard let start = utf16.index(utf16.startIndex, offsetBy: window.lowerBound, limitedBy: utf16.endIndex),
            let end = utf16.index(start, offsetBy: window.count, limitedBy: utf16.endIndex)
        else { return whole }
        return String(utf16[start..<end]) ?? whole
    }

    /// On the session thread: removes the notifications and the run loop source.
    private func stopObserving() {
        if let activation {
            NSWorkspace.shared.notificationCenter.removeObserver(activation)
        }
        activation = nil
        if let observer {
            AXObserverRemoveNotification(observer, element, kAXValueChangedNotification as CFString)
            AXObserverRemoveNotification(observer, element, kAXUIElementDestroyedNotification as CFString)
            AXObserverRemoveNotification(observer, application, kAXFocusedUIElementChangedNotification as CFString)
            CFRunLoopRemoveSource(CFRunLoopGetCurrent(), AXObserverGetRunLoopSource(observer), .defaultMode)
        }
        observer = nil
        continuation.finish()
    }

    // MARK: Attributes

    private static func attribute(_ name: String, of element: AXUIElement, as typeID: CFTypeID? = nil) -> CFTypeRef? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success, let value,
            typeID.map({ CFGetTypeID(value) == $0 }) ?? true
        else { return nil }
        return value
    }

    private static func characterCount(of element: AXUIElement) -> Int? {
        attribute(kAXNumberOfCharactersAttribute, of: element, as: CFNumberGetTypeID()) as? Int
    }

    private static func selectedRange(of element: AXUIElement) -> CFRange? {
        guard let value = attribute(kAXSelectedTextRangeAttribute, of: element, as: AXValueGetTypeID()) else {
            return nil
        }
        var range = CFRange()
        return AXValueGetValue(unsafeDowncast(value, to: AXValue.self), .cfRange, &range) ? range : nil
    }
}

/// A C callback cannot capture: the field comes back through `refcon`. It runs on the session thread, where the
/// observer's run loop source is.
private func fieldCallback(
    _: AXObserver, element: AXUIElement, notification: CFString, refcon: UnsafeMutableRawPointer?
) {
    guard let refcon else { return }
    Unmanaged<AXFocusedField>.fromOpaque(refcon).takeUnretainedValue().received(notification as String, from: element)
}

/// One thread with its own run loop for one readback session: the AX calls and the observer's callbacks run here
/// (the header says to add the source "to the run loop on which you want the callback executed",
/// AXNotificationConstants.h). It starts when a paste opens a field and exits when the session closes, so between
/// sessions there is no thread and no work. Cost per paste: one thread start (tens of microseconds).
///
/// `@unchecked Sendable`: `runLoop` is set once before `start()` returns; `isStopped` is behind its Mutex; CFRunLoop's
/// perform and wake-up calls are thread-safe.
final class SessionThread: @unchecked Sendable {
    private let runLoop: CFRunLoop
    /// Set by `stop()`. A block is queued only while it is false, and the stop itself is queued last, so every queued
    /// block runs and none waits for ever.
    private let isStopped = Mutex(false)

    private init(runLoop: CFRunLoop) {
        self.runLoop = runLoop
    }

    static func start() async -> SessionThread {
        await withCheckedContinuation { continuation in
            let thread = Thread {
                // A port keeps the run loop running while the session waits for notifications; it never fires.
                RunLoop.current.add(NSMachPort(), forMode: .default)
                continuation.resume(returning: SessionThread(runLoop: CFRunLoopGetCurrent()))
                CFRunLoopRun()
            }
            thread.name = "kotoba readback"
            thread.qualityOfService = .userInitiated
            thread.start()
        }
    }

    /// Runs `work` on the thread and returns its result; nil once the thread was stopped.
    func run<Result: Sendable>(_ work: @escaping @Sendable () -> Result) async -> Result? {
        await withCheckedContinuation { continuation in
            let isQueued = isStopped.withLock { isStopped in
                guard !isStopped else { return false }
                enqueue { continuation.resume(returning: work()) }
                return true
            }
            if !isQueued {
                continuation.resume(returning: nil)
            }
        }
    }

    /// The blocks queued before run, then the run loop returns and the thread exits.
    func stop() {
        isStopped.withLock { isStopped in
            guard !isStopped else { return }
            isStopped = true
            enqueue { CFRunLoopStop(CFRunLoopGetCurrent()) }
        }
    }

    private func enqueue(_ block: @escaping @Sendable () -> Void) {
        CFRunLoopPerformBlock(runLoop, CFRunLoopMode.defaultMode.rawValue, block)
        CFRunLoopWakeUp(runLoop)
    }
}

/// Turns the edits `EditReadback` reports into dictionary entries (docs/spec.md, Owner round 2026-10-16): a strong
/// correction is added at once and the pill shows it with Undo; a weak one waits in Suggestions. The detector and the
/// spell checker it loads (about 1.3 MB, 10-50 ms on first use) run only between dictations: an edit that comes while
/// a dictation records or is sent waits until it is done.
@MainActor
final class EditLearner {
    /// The pipeline's port: it follows the field after each paste, and observes nothing between sessions.
    let readback = EditReadback(watcher: AXFieldWatcher(), clock: SystemClock())
    private let dictionary: @MainActor () -> DictionaryModel?
    private let indicator: IndicatorPanel
    /// What the pill's Undo takes out again, by the id the pill carries.
    private var lastLearned: LastLearn?

    private struct LastLearn {
        var id: UUID
        var entries: DictionaryModel.Learned
    }
    /// Edits that came during a dictation, learned when it is done.
    private var waiting: [EditReadback.Edit] = []
    private var isDictating = false
    private var isEnabled = AppDefaults.isLearningFromEdits
    private var tasks: [Task<Void, Never>] = []

    init(dictionary: @escaping @MainActor () -> DictionaryModel?, indicator: IndicatorPanel) {
        self.dictionary = dictionary
        self.indicator = indicator
        let readback = readback
        tasks.append(
            Task { [weak self] in
                for await edit in readback.edits {
                    self?.received(edit)
                }
            })
        // The "Learn from my edits" switch writes UserDefaults; each change in this process posts this.
        tasks.append(
            Task { [weak self] in
                await readback.setEnabled(AppDefaults.isLearningFromEdits)
                for await _ in NotificationCenter.default.notifications(named: UserDefaults.didChangeNotification) {
                    await self?.learningSettingChanged()
                }
            })
    }

    /// Every dictation state from the pipeline: learning waits while a dictation records, is sent or can be undone.
    func dictationStateChanged(_ state: DictationState) {
        isDictating =
            switch state {
            case .recording, .transcribing, .undoable: true
            default: false
            }
        guard !isDictating, !waiting.isEmpty else { return }
        let edits = waiting
        waiting = []
        edits.forEach(learn(from:))
    }

    /// The pill's Undo: removes exactly the entries that learn added.
    func undo(_ id: UUID) {
        guard let learned = lastLearned, learned.id == id, let model = dictionary() else { return }
        lastLearned = nil
        model.undoLearned(learned.entries)
    }

    private func learningSettingChanged() async {
        let isOn = AppDefaults.isLearningFromEdits
        guard isOn != isEnabled else { return }
        isEnabled = isOn
        if !isOn {
            waiting = []
        }
        await readback.setEnabled(isOn)
    }

    private func received(_ edit: EditReadback.Edit) {
        guard isEnabled else { return }
        if isDictating {
            waiting.append(edit)
        } else {
            learn(from: edit)
        }
    }

    private func learn(from edit: EditReadback.Edit) {
        guard isEnabled, let model = dictionary() else { return }
        let corrections = CorrectionDetector.corrections(
            pasted: edit.pasted, observed: edit.edited, dictionary: model.dictionary, dismissed: model.dismissedPairs,
            origin: .edit, isKnownWord: DictionaryModel.isKnownWord
        ).map { correction in
            var correction = correction
            correction.candidate.appBundleID = edit.appBundleID
            return correction
        }
        let choice = ReadbackChoice(corrections: corrections, of: edit)
        if !choice.suggest.isEmpty {
            model.record(choice.suggest)
        }
        guard let entries = model.learn(choice.add) else { return }
        let id = UUID()
        let label = entries.words.count == 1 ? entries.words[0] : StatusText.counted(entries.words.count, "word")
        lastLearned = LastLearn(id: id, entries: entries)
        indicator.show(.learned(label, id: id))
    }
}
