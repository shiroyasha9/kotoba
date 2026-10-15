import Foundation

/// The text field kotoba pasted into, followed while a readback session lasts. The App's adapter reads it through
/// Accessibility notifications and never opens a secure field (docs/research/auto-learning.md, Readback).
public protocol FocusedField: Sendable {
    /// The app that owns the field; what kotoba learns there names it.
    var appBundleID: String? { get }
    /// The owner's changes, and focus leaving, until `close()`.
    var events: AsyncStream<FieldEvent> { get }
    /// The field's text within `radius` UTF-16 units on each side of the insertion point; nil when it cannot be read.
    func read(radius: Int) async -> String?
    /// Stops the notifications and releases the field.
    func close() async
}

public enum FieldEvent: Sendable, Equatable {
    /// The field's text changed.
    case changed
    /// Focus moved to another element or app, or the field went away.
    case left
}

/// Opens the focused field of the frontmost app after a paste.
public protocol FieldWatcher: Sendable {
    /// Nil for a secure field, an app without readable text (terminals), or no Accessibility access.
    func focusedField() async -> (any FocusedField)?
}

/// Follows the field after each paste and reports the owner's edit of the pasted text (docs/spec.md, Owner round
/// 2026-10-16). Event-driven: the field is read once the changes stop for `settle`, or at the latest `maxWait` after the
/// first change not read yet, and once more when focus leaves with a change not read yet. A session ends on the time
/// limit, on focus leaving, when the pasted text is gone, at the next dictation (which never waits for a read), or
/// when learning is turned off. Between sessions nothing is observed.
public actor EditReadback {
    public struct Settings: Sendable {
        /// Quiet time after the last change before the field is read: the owner stopped typing.
        public var settle: Duration
        /// A field that keeps changing (a terminal redrawing) is read at the latest this long after its first change
        /// not read yet, so a sent or cleared field ends the session in seconds.
        public var maxWait: Duration
        /// A session ends this long after the paste.
        public var timeLimit: Duration
        /// Longer dictations are not followed: the alignment cost grows with the square of the words.
        public var maxPastedWords: Int

        public init(
            settle: Duration = .milliseconds(500), maxWait: Duration = .seconds(2), timeLimit: Duration = .seconds(60),
            maxPastedWords: Int = 200
        ) {
            self.settle = settle
            self.maxWait = maxWait
            self.timeLimit = timeLimit
            self.maxPastedWords = maxPastedWords
        }
    }

    /// The pasted text and the owner's version of it, both in memory only.
    public struct Edit: Sendable, Equatable {
        public var pasted: String
        public var edited: String
        public var appBundleID: String?
        public var endedBy: EndReason
        /// The field did not change after the read that gave `edited`, except for the one change that removed the
        /// text (a sent message). False when the owner may have typed on: `edited` can hold half a word.
        public var isSettled: Bool
    }

    public enum EndReason: Sendable, Equatable {
        case timeLimit
        /// Focus left the field or its app.
        case focusLeft
        /// The pasted text is no longer in the field: sent, cleared or rewritten.
        case textGone
        /// A new dictation started, or the next paste came.
        case nextDictation
    }

    /// One edit per session in which the owner changed the pasted text.
    public nonisolated let edits: AsyncStream<Edit>
    private let editsContinuation: AsyncStream<Edit>.Continuation
    private let watcher: any FieldWatcher
    private let clock: any PipelineClock
    private let settings: Settings
    private let work: PendingWork
    /// "Learn from my edits". Off, no field is opened and an open session ends with no edit.
    private var isEnabled = true
    /// Counts sessions, so a field that opens after its session ended is closed at once.
    private var generation = 0
    private var session: Session?

    private struct Session {
        let generation: Int
        let pasted: String
        let field: any FocusedField
        /// The pasted span at the last read, with the owner's edits; nil before the first read.
        var edited: String?
        /// Changes posted after the last read that found the span.
        var unreadChanges = 0
        var lastChangeAt: ContinuousClock.Instant?
        /// The first change since the last read began; nil when every change was read.
        var firstUnreadChangeAt: ContinuousClock.Instant?
        /// One timer at a time; it re-arms itself while changes come, instead of one timer per change.
        var readTimer: Task<Void, Never>?
        let timeLimit: Task<Void, Never>
        let events: Task<Void, Never>

        /// When the next read is due: after a quiet `settle`, and at the latest `maxWait` after the first unread
        /// change.
        func readDue(_ settings: Settings) -> ContinuousClock.Instant? {
            guard let lastChangeAt, let firstUnreadChangeAt else { return nil }
            return min(lastChangeAt + settings.settle, firstUnreadChangeAt + settings.maxWait)
        }
    }

    public init(watcher: any FieldWatcher, clock: any PipelineClock, settings: Settings = Settings()) {
        self.watcher = watcher
        self.clock = clock
        self.settings = settings
        work = PendingWork(clock: clock)
        (edits, editsContinuation) = AsyncStream.makeStream(of: Edit.self)
    }

    /// kotoba pasted `text`: follow the focused field. A session still open ends first.
    public func pasted(_ text: String) {
        end(.nextDictation, isSettled: isSettledNow)
        generation += 1
        let pasted = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let words = pasted.split(whereSeparator: \.isWhitespace).count
        guard isEnabled, words > 0, words <= settings.maxPastedWords else { return }
        work.track { [generation] in await self.open(pasted, generation: generation) }
    }

    /// A dictation starts: the session ends without another read, and a field still opening is closed.
    public func dictationStarted() {
        generation += 1
        end(.nextDictation, isSettled: isSettledNow)
    }

    /// "Learn from my edits" turned on or off. Off ends the open session at once and reports nothing from it.
    public func setEnabled(_ isOn: Bool) {
        isEnabled = isOn
        guard !isOn else { return }
        generation += 1
        end(.nextDictation, isSettled: isSettledNow, reporting: false)
    }

    /// The part of a field of `length` UTF-16 units to read: `radius` on each side of the insertion point. A caret
    /// another app reports as not found (`NSNotFound`, or a negative location) or past the end is clamped first.
    public nonisolated static func readRange(caret: Int, length: Int, radius: Int) -> Range<Int> {
        let length = max(length, 0)
        let caret = min(max(caret, 0), length)
        return max(0, caret - radius)..<(caret + min(radius, length - caret))
    }

    private func open(_ pasted: String, generation: Int) async {
        guard let field = await watcher.focusedField() else { return }
        guard generation == self.generation, session == nil else {
            await field.close()
            return
        }
        let events = Task {
            for await event in field.events {
                await self.handle(event, generation: generation)
            }
        }
        let timeLimit = work.schedule(at: clock.now + settings.timeLimit) {
            await self.finish(.timeLimit, generation: generation)
        }
        session = Session(generation: generation, pasted: pasted, field: field, timeLimit: timeLimit, events: events)
    }

    private func handle(_ event: FieldEvent, generation: Int) async {
        guard session?.generation == generation else { return }
        switch event {
        case .changed:
            let now = clock.now
            session?.unreadChanges += 1
            session?.lastChangeAt = now
            if session?.firstUnreadChangeAt == nil {
                session?.firstUnreadChangeAt = now
            }
            if session?.readTimer == nil {
                armReadTimer(generation: generation)
            }
        case .left:
            await finish(.focusLeft, generation: generation)
        }
    }

    private func armReadTimer(generation: Int) {
        guard let due = session?.readDue(settings) else { return }
        session?.readTimer = work.schedule(at: due) { await self.readTimerFired(generation: generation) }
    }

    /// Reads when the read is due; when changes came meanwhile, waits again until it is.
    private func readTimerFired(generation: Int) async {
        guard let current = session, current.generation == generation else { return }
        session?.readTimer = nil
        guard let due = current.readDue(settings) else { return }
        if clock.now < due {
            armReadTimer(generation: generation)
        } else {
            await read(generation: generation)
        }
    }

    /// Focus left: the owner is done, so a change not read yet is read now. The time limit can come while the owner
    /// types, so it does not read: an unread change makes the edit unsettled.
    private func finish(_ reason: EndReason, generation: Int) async {
        guard let current = session, current.generation == generation else { return }
        if reason == .focusLeft, current.unreadChanges > 0 {
            current.readTimer?.cancel()
            session?.readTimer = nil
            guard await read(generation: generation) else { return }
        }
        end(reason, isSettled: isSettledNow)
    }

    /// Keeps the pasted span as the field shows it now, and ends the session when the pasted text is gone. False
    /// when the session ended, during the read or because of it.
    @discardableResult
    private func read(generation: Int) async -> Bool {
        guard let current = session else { return false }
        let changesBefore = current.unreadChanges
        // A change during the read counts as after it.
        session?.firstUnreadChangeAt = nil
        // From any insertion point inside the span, the whole span with some edits.
        let radius = current.pasted.utf16.count + 64
        let text = await current.field.read(radius: radius)
        guard let now = session, now.generation == generation else { return false }
        guard let text, let span = PastedSpan.find(current.pasted, in: text) else {
            // Settled when the only change after the last good read is the one that removed the text.
            end(.textGone, isSettled: changesBefore <= 1 && now.unreadChanges == changesBefore)
            return false
        }
        session?.edited = span
        session?.unreadChanges -= changesBefore
        return true
    }

    /// Releases the field and reports the last edit seen, unless `reporting` is false.
    private func end(_ reason: EndReason, isSettled: Bool, reporting: Bool = true) {
        guard let current = session else { return }
        session = nil
        current.readTimer?.cancel()
        current.timeLimit.cancel()
        current.events.cancel()
        work.track { await current.field.close() }
        guard reporting, let edited = current.edited, edited != current.pasted else { return }
        editsContinuation.yield(
            Edit(
                pasted: current.pasted, edited: edited, appBundleID: current.field.appBundleID, endedBy: reason,
                isSettled: isSettled))
    }

    /// No change came after the last read.
    private var isSettledNow: Bool {
        session?.unreadChanges == 0
    }

    var isFollowing: Bool {
        session != nil
    }

    /// Waits for all work that can finish now; tests call it after each step.
    func settle() async {
        await work.settle()
    }
}

/// Where the pasted transcript is in the field's text now, with the owner's edits. A word alignment that uses every
/// pasted word and may start and end anywhere in the field: the text around the paste costs nothing, and each added
/// or removed word costs 1. A changed word costs 1 too, but only half when the two words share most of their letters
/// (`Mellow` -> `Marlow`), so a respelled first or last word stays in the span while an unrelated word next to the
/// paste stays out. Words match on their letters (`CorrectionDetector.letterKey`): case and punctuation do not count.
/// No anchors are needed, so a field read only after the owner's first change works too.
enum PastedSpan {
    /// Edits that cost more than this share of the pasted words (and more than one word): the text is gone (sent,
    /// cleared or rewritten).
    static let maxCostShare = 0.5
    /// Costs in half words, so the alignment adds integers.
    private static let word = 2
    private static let respelledWord = 1

    /// The part of `text` that is the pasted transcript after the owner's edits; nil when it is not there.
    static func find(_ pasted: String, in text: String) -> String? {
        let source = pasted.split(whereSeparator: \.isWhitespace)
        let target = text.split(whereSeparator: \.isWhitespace)
        guard !source.isEmpty, !target.isEmpty else { return nil }
        if text.contains(pasted) { return pasted }
        var ids: [[Character]: Int] = [:]
        var letters: [UInt32] = []
        func id(_ word: Substring) -> Int {
            let key = CorrectionDetector.letterKey(String(word))
            if let id = ids[key] { return id }
            ids[key] = ids.count
            letters.append(key.reduce(0) { $0 | 1 << ($1.unicodeScalars.first.map { $0.value % 32 } ?? 0) })
            return ids.count - 1
        }
        let (cost, span) = align(source.map(id), target.map(id), letters: letters)
        guard Double(cost) <= max(1, maxCostShare * Double(source.count)) * Double(word), let first = span.first,
            let last = span.last
        else { return nil }
        return String(text[target[first].startIndex..<target[last].endIndex])
    }

    /// The cheapest alignment of every `source` word with a run of `target` words: its cost, and the target words
    /// it covers. Words are numbers (equal words, equal numbers); `letters` holds each number's set of letters.
    private static func align(_ sourceWords: [Int], _ targetWords: [Int], letters: [UInt32]) -> (
        cost: Int, span: Range<Int>
    ) {
        let width = targetWords.count + 1
        // cost[j]: the cheapest alignment of the pasted words so far that ends before field word j; start[j]: the
        // field word it starts at. Row 0 starts anywhere for free. Raw buffers: this loop runs for every pair of
        // words, and checked arrays made it about 15 times slower in a Debug build.
        var cost = UnsafeMutableBufferPointer<Int>.allocate(capacity: width)
        var nextCost = UnsafeMutableBufferPointer<Int>.allocate(capacity: width)
        var start = UnsafeMutableBufferPointer<Int>.allocate(capacity: width)
        var nextStart = UnsafeMutableBufferPointer<Int>.allocate(capacity: width)
        let targetLetters = UnsafeMutableBufferPointer<UInt32>.allocate(capacity: targetWords.count)
        defer {
            for buffer in [cost, nextCost, start, nextStart] { buffer.deallocate() }
            targetLetters.deallocate()
        }
        _ = cost.initialize(from: repeatElement(0, count: width))
        _ = nextCost.initialize(from: repeatElement(0, count: width))
        _ = start.initialize(from: 0..<width)
        _ = nextStart.initialize(from: 0..<width)
        _ = targetLetters.initialize(from: targetWords.map { letters[$0] })
        for sourceWord in sourceWords {
            let sourceLetters = letters[sourceWord]
            nextCost[0] = cost[0] + word
            nextStart[0] = start[0]
            for column in 1..<width {
                let previous = column - 1
                let diagonal =
                    cost[previous] + change(sourceWord, sourceLetters, targetWords[previous], targetLetters[previous])
                let removed = cost[column] + word
                let added = nextCost[previous] + word
                // On a tie, a changed word beats a removed one at the start of the span.
                if diagonal <= removed, diagonal <= added {
                    nextCost[column] = diagonal
                    nextStart[column] = start[previous]
                } else if removed <= added {
                    nextCost[column] = removed
                    nextStart[column] = start[column]
                } else {
                    nextCost[column] = added
                    nextStart[column] = nextStart[previous]
                }
            }
            swap(&cost, &nextCost)
            swap(&start, &nextStart)
        }
        // The cheapest end; the earlier one on a tie, so an unrelated word after the paste stays out.
        var end = 0
        for column in 0..<width where cost[column] < cost[end] {
            end = column
        }
        return (cost[end], start[end]..<end)
    }

    /// 0 for the same word; half a word when the two share at least half of their letters (letter sets, so the test
    /// costs two bit counts); else a word.
    private static func change(_ source: Int, _ sourceLetters: UInt32, _ target: Int, _ targetLetters: UInt32) -> Int {
        if source == target { return 0 }
        let shared = (sourceLetters & targetLetters).nonzeroBitCount
        return 2 * shared >= (sourceLetters | targetLetters).nonzeroBitCount && shared > 0 ? respelledWord : word
    }
}
