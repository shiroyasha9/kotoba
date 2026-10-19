import Foundation

/// The one way kotoba puts text into the owner's app (docs/spec.md, "Paste"): a dictation, Polish and its Undo, Paste
/// Last and Paste Again each run one paste transaction through `run(_:gate:)`. It decides whether the text may paste
/// (kotoba quits, a dictation came first, the owner is away, another app is in front), writes it as a transient item
/// over the owner's clipboard, reads where the owner is, sends the Backspaces, the ⌘V and the Return, and the owner's
/// clipboard comes back `readSettle` after the paste target read the text (`ClipboardGuard`). A paste that no app read
/// is reported to the gate. Callers never post a paste key or write a transient item themselves (lint
/// `one_paste_path`).
///
/// A Sendable struct, not on the pipeline actor: the work between the gate and the ⌘V runs on the clipboard's own
/// actor and the ports, so a key event never waits for it.
struct ClipboardPaste: Sendable {
    /// The owner's clipboard, read at the announcement while capture runs, and when it was ready (`snapshotReady`).
    typealias PendingSnapshot = ClipboardGuard.Pending

    /// One paste: `text` of dictation `id`, for `app`.
    struct Request: Sendable {
        let id: DictationID
        let text: String
        let kind: Kind
        /// The app the text is for: the one in front at the stop, or when the owner asked. Another app in front gets no
        /// paste. Nil when it was not known: nothing says it changed.
        let app: FrontApp?
        /// The clipboard taken at the announcement; nil reads it now.
        var snapshot: PendingSnapshot?
    }

    enum Kind: Sendable, Equatable {
        /// A dictation's own paste. The gate waits for the release of `stoppingPress`; Return follows the ⌘V when
        /// the transcript `submits` or the owner asks for it (`PasteGate.isSubmitAsked`).
        case dictation(stoppingPress: Int?, submits: Bool)
        /// Paste Last, Paste Again: a stored text.
        case again
        /// Polish or its Undo: `backspaces` Backspaces delete the old text right before the ⌘V (0 pastes over the
        /// selection). They were judged safe at `place` (`PolishPlacement`), so they go only while the place read
        /// right before the ⌘V is still that one: same app and window, no key or click since.
        case polish(backspaces: Int, at: InputMark?)
    }

    /// What the pipeline knows once a ⌘V could go out (`PasteGate.facts(for:)`).
    struct Facts: Sendable {
        var isQuitting = false
        var isPresent = true
        /// A dictation (or, for Paste Again, a Polish) came since the owner asked: its text is where this one would
        /// paste.
        var isOvertaken = false
    }

    enum Outcome: Sendable, Equatable {
        case pasted(Pasted)
        /// Not allowed here (the owner is away, another app is in front, the ⌘V or Backspace was refused): the text
        /// waits on the clipboard, with no restore.
        case copied
        /// Nothing done and the clipboard untouched: kotoba quits, or a dictation came first.
        case skipped
    }

    struct Pasted: Sendable, Equatable {
        /// When the ⌘V went out (`pasteSent`).
        let sentAt: ContinuousClock.Instant
        /// False when the clipboard before was too large to keep: it does not come back.
        let isClipboardKept: Bool
        /// Where the owner was right before the ⌘V; nil while Polish is off, as nothing reads it then.
        let place: InputMark?
        /// The Return after a dictation's ⌘V; nil when none was asked for.
        let submit: Submit?
    }

    enum Submit: Sendable, Equatable {
        case sent(at: ContinuousClock.Instant)
        /// A Return in another app could run the pasted text as a command there.
        case frontAppChanged
        case failed
    }

    /// A read before the Cmd-V (a clipboard manager that ignores the markers) takes the one read signal, so the
    /// target's own read cannot be seen: the clipboard comes back this long after the Cmd-V, the rule before the read
    /// signal (Jot and FreeFlow use 1 s too).
    static let earlyReadRestoreDelay = Duration.seconds(1)
    /// From the paste target's read to the restore. The read is when the target asks for the text, not when it has
    /// it, and macOS tells the writer nothing later: the pasteboard can still be handing the text over (0.1-0.5 ms in a
    /// spike, about 1 ms in cmux), and a target can check the change count again after its read (cmux drops the paste
    /// when it moved) or read again in the same paste (Chromium). A restore in that time pastes nothing or the old
    /// clipboard (2026-10-19, docs/research/paste-restore.md). 200 ms as in Handy (owner, 2026-10-19); revisit with
    /// the notes in that file if a paste is lost again.
    static let readSettle = Duration.milliseconds(200)

    private let clipboard: ClipboardGuard
    private let paster: any Paster
    private let frontApp: @Sendable () -> FrontApp?
    /// Where the owner is now; nil while Polish is off. One window list read on the paste path: 0.2 ms p50, 0.5 ms
    /// p90; the first in a process takes 20-40 ms, and the indicator's first key-down already pays it.
    private let place: (@Sendable () -> InputMark?)?
    /// An app that read nothing by then never got the paste (`Settings.readWait`).
    private let readWait: Duration
    private let clock: any PipelineClock

    init(
        pasteboard: any Pasteboard, paster: any Paster, frontApp: @escaping @Sendable () -> FrontApp?,
        place: (@Sendable () -> InputMark?)?, readWait: Duration, work: PendingWork, clock: any PipelineClock
    ) {
        clipboard = ClipboardGuard(pasteboard: pasteboard, work: work, clock: clock)
        self.paster = paster
        self.frontApp = frontApp
        self.place = place
        self.readWait = readWait
        self.clock = clock
    }

    /// Starts reading the owner's clipboard, at the announcement: reading promised data can be slow.
    func snapshot() -> PendingSnapshot {
        Task { [clipboard, clock] in (snapshot: await clipboard.snapshot(), readyAt: clock.now) }
    }

    /// Runs one paste transaction. The gate is asked once the clipboard is read, right before the write, so what it
    /// says is still true at the ⌘V; a paste no app read within `readWait` is reported to it later.
    func run(_ request: Request, gate: some PasteGate) async -> Outcome {
        let snapshot =
            if let pending = request.snapshot { await pending.value.snapshot } else { await clipboard.snapshot() }
        let facts = await gate.facts(for: request)
        guard !facts.isQuitting, !facts.isOvertaken else {
            // Quit returns before a restore could run, so the clipboard is left alone; Paste Last finds the text at
            // the next launch. A dictation or Polish that came first owns the clipboard now.
            Log.pipeline.info("Not pasted or copied: kotoba is quitting, or a dictation or Polish came first")
            return .skipped
        }
        // The owner went to another app after the stop (a late answer) or since asking: the text never goes there, it
        // waits on the clipboard (lead, 2026-10-17).
        guard facts.isPresent, !isFrontAppChanged(from: request.app) else {
            Log.pipeline.info("Not pasted (owner away, or another app in front); the text is on the clipboard")
            await clipboard.copy(request.text)
            return .copied
        }
        // The report waits up to `readWait`: it holds no snapshot, which can be up to `PasteboardSnapshot.byteLimit`.
        let reported = Request(id: request.id, text: request.text, kind: request.kind, app: request.app)
        let write = await clipboard.writeForPaste(request.text, over: snapshot, readBy: clock.now + readWait) {
            await gate.pasteWentUnread(reported, isLeftOnClipboard: $0)
        }
        // Read after the write, right before the ⌘V, so a window switch during the write cannot leave a wrong place.
        let place = place?()
        if case .polish(let backspaces, let judgedAt) = request.kind, backspaces > 0, place != judgedAt {
            Log.pipeline.info("Polish: the owner typed or moved during the write; the text goes to the clipboard")
            await clipboard.copy(request.text)
            return .copied
        }
        do {
            if case .polish(let backspaces, _) = request.kind, backspaces > 0 {
                try await paster.sendBackspaces(backspaces)
            }
            try await paster.sendPaste()
        } catch {
            Log.pipeline.error("Paste not allowed, the text is left on the clipboard: \(error)")
            await clipboard.copy(request.text)
            return .copied
        }
        let sentAt = clock.now
        var submit: Submit?
        if case .dictation(_, let submits) = request.kind, submits ? true : await gate.isSubmitAsked(request) {
            submit = await sendReturn(to: request.app)
        }
        return .pasted(Pasted(sentAt: sentAt, isClipboardKept: write.isClipboardKept, place: place, submit: submit))
    }

    /// Another app is in front than `app`. With no app known then, or now, nothing says it changed. Polish asks before
    /// it selects the old text, so it touches no field of an app the owner left.
    func isFrontAppChanged(from app: FrontApp?) -> Bool {
        guard let app, let now = frontApp() else { return false }
        return now.processID != app.processID
    }

    /// Return right after the Cmd-V, into the same event stream; the chord is already released. Stricter than the
    /// paste's rule: an app not known at the stop or now gets no Return, as a Return can run the text as a command.
    private func sendReturn(to app: FrontApp?) async -> Submit {
        guard frontApp()?.processID == app?.processID else {
            Log.pipeline.info("Return not sent: the front app changed after the stop")
            return .frontAppChanged
        }
        do {
            try await paster.sendReturn()
            return .sent(at: clock.now)
        } catch {
            Log.pipeline.error("Return not sent after the paste: \(error)")
            return .failed
        }
    }

    /// Leaves `text` on the clipboard for the owner to paste, with no restore.
    func copy(_ text: String) async {
        await clipboard.copy(text)
    }

    /// Quit: returns once no paste waits for its read and restore, or at `deadline`. An unread paste's text then stays
    /// (AppKit hands over every promise at quit).
    func waitUntilRestored(by deadline: ContinuousClock.Instant) async {
        await clipboard.waitUntilRestored(by: deadline)
    }

    /// Test seam: whether quit waits for a restore.
    var isQuitWaiting: Bool {
        get async { await clipboard.isQuitWaiting }
    }
}

/// What only the pipeline knows about a paste (`ClipboardPaste.run(_:gate:)`); the pipeline is the gate, and tests
/// use a fake.
protocol PasteGate: Sendable {
    /// Returns once a ⌘V can go out for `request` (a dictation's waits for the chord's release), with what is true
    /// then.
    func facts(for request: ClipboardPaste.Request) async -> ClipboardPaste.Facts
    /// Right after a dictation's ⌘V: the owner stopped it with Return, or pressed Return just after the stop.
    func isSubmitAsked(_ request: ClipboardPaste.Request) async -> Bool
    /// No app read the paste of `request` within the read wait, or the next paste replaced it first: it did not land.
    /// `isLeftOnClipboard` is true when its text stays on the clipboard.
    func pasteWentUnread(_ request: ClipboardPaste.Request, isLeftOnClipboard: Bool) async
}
