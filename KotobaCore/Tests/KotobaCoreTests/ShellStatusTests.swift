import Foundation
import Testing

@testable import KotobaCore

struct ShellStatusTests {
    private static let listening = DictationState(.recording(isLong: false))

    /// A notice over no live dictation.
    private static func notice(_ notice: DictationNotice) -> DictationState {
        DictationState(.idle, notice: notice)
    }

    /// Each state in turn from a fresh shell, and the cue each one plays.
    private static func cues(_ states: [DictationState]) -> [CueVoice.Cue?] {
        var shell = ShellStatus()
        return states.map { shell.dictationChanged($0).cue }
    }

    @Test func aDictationPlaysOneStartAndOneStopCue() {
        let states: [DictationState] = [
            Self.listening, .init(.recording(isLong: true)), .init(.recording(isLong: true, isSilent: true)),
            .init(.transcribing), .init(.cleaning), .idle,
        ]
        #expect(Self.cues(states) == [.start, nil, nil, .stop, nil, nil])
    }

    /// Esc cancels with no stop cue, and Undo resumes the same recording: the start cue sounds again for it.
    @Test func aCanceledRecordingPlaysNoStopCue() {
        #expect(
            Self.cues([Self.listening, .init(.undoable), Self.listening, .init(.transcribing)])
                == [.start, nil, .start, .stop])
        #expect(Self.cues([Self.listening, Self.notice(.nothingRecorded)]) == [.start, nil])
    }

    /// A transcribing state that does not follow a recording (Transcribe Again, a retry) is no stop.
    @Test func aStopCueOnlyEndsARecording() {
        #expect(Self.cues([.init(.transcribing), .idle, .init(.transcribing)]) == [nil, nil, nil])
    }

    @Test func aRecordingStartReadsSecureInputOnceAndShowsTheRecording() {
        var shell = ShellStatus()
        #expect(
            shell.dictationChanged(Self.listening)
                == .init(cue: .start, readsSecureInput: true, isRecordingShown: true))
        #expect(shell.dictationChanged(.init(.recording(isLong: true))) == .init(isRecordingShown: true))
        #expect(shell.dictationChanged(.init(.transcribing)) == .init(cue: .stop))
    }

    /// b235fa0: Microphone access turned off while kotoba runs makes the mic silent; the silent pill reads the grants
    /// again, so it can say access is off.
    @Test func aSilentRecordingReadsTheGrantsAgain() {
        var shell = ShellStatus()
        _ = shell.dictationChanged(Self.listening)
        let silent = shell.dictationChanged(.init(.recording(isLong: false, isSilent: true)))
        #expect(silent.readsGrants)
        #expect(silent.cue == nil)
        #expect(!shell.dictationChanged(Self.listening).readsGrants)
    }

    /// I2: a capture that did not start and a copy instead of a paste say what the grants allow now.
    @Test func aFailedCaptureAndACopyReadTheGrantsAgain() {
        var shell = ShellStatus()
        #expect(shell.dictationChanged(Self.notice(.captureFailed)).readsGrants)
        #expect(shell.dictationChanged(Self.notice(.copied(DictationID()))).readsGrants)
        #expect(!shell.dictationChanged(Self.notice(.failed(DictationID()))).readsGrants)
        #expect(!shell.dictationChanged(.idle).readsGrants)
    }

    /// 3a9743b: a recovered text the store could not write has no history write to announce it, so the recovered
    /// state itself reads the queues.
    @Test func aRecoveredTextReadsTheQueues() {
        var shell = ShellStatus()
        #expect(shell.dictationChanged(Self.notice(.recovered(DictationID()))) == .init(readsQueues: true))
        #expect(!shell.dictationChanged(Self.notice(.copied(DictationID()))).readsQueues)
    }

    // MARK: Icon

    private typealias Facts = ShellStatus.Facts<String>

    private static func view(_ state: DictationState, _ facts: Facts = .init(), waiting: Int = 0)
        -> ShellStatus.View<String>
    {
        var shell = ShellStatus()
        _ = shell.dictationChanged(state)
        _ = shell.queueReadRequested()
        _ = shell.queueRead(
            .init(waitingCount: waiting, recovered: [], hasLastDictation: false, hasRawLastDictation: false))
        return shell.view(facts)
    }

    @Test func theIconListensWhileRecordingWhateverNeedsAttention() {
        #expect(Self.view(.idle).icon == .ready)
        #expect(Self.view(.init(.transcribing)).icon == .ready)
        #expect(
            Self.view(Self.listening, .init(firstMissing: "key", hasWaitingUpdate: true), waiting: 2).icon == .listening
        )
    }

    @Test func setupAWaitingRetryOrAWaitingUpdateNeedAttention() {
        #expect(Self.view(.idle, .init(firstMissing: "key")).icon == .needsAttention)
        #expect(Self.view(.idle, waiting: 1).icon == .needsAttention)
        #expect(Self.view(.idle, .init(hasWaitingUpdate: true)).icon == .needsAttention)
        #expect(Self.view(.idle, .init(isYielding: true)).icon == .ready)
    }

    // MARK: Menu status

    @Test func anIdleMenuSaysWhatSetupNeedsElseHowToDictate() {
        #expect(Self.view(.idle).status == .ready)
        #expect(Self.view(.idle, .init(firstMissing: "key")).status == .finishSetup("key"))
    }

    /// A dictation's own words come first, also while setup is not complete.
    @Test func aDictationSaysItsOwnWords() {
        let failed = Self.notice(.failed(DictationID()))
        #expect(Self.view(failed, .init(firstMissing: "key")).status == .dictation(failed))
        #expect(Self.view(.init(.transcribing)).status == .dictation(.init(.transcribing)))
    }

    /// 2c02ed2, 80bfa83: a development build says it gives way while the release app runs. A live dictation's own
    /// text comes first; an outcome is past, and the next chord goes to the release app.
    @Test func theMenuSaysItGivesWayExceptDuringALiveDictation() {
        let yielding = Facts(firstMissing: "key", isYielding: true)
        #expect(Self.view(.idle, yielding).status == .yieldsToRelease)
        #expect(Self.view(Self.notice(.failed(DictationID())), yielding).status == .yieldsToRelease)
        #expect(Self.view(Self.notice(.copied(DictationID())), yielding).status == .yieldsToRelease)
        for phase: DictationPhase in [.recording(isLong: false), .transcribing, .cleaning, .undoable, .polishing] {
            #expect(Self.view(.init(phase), yielding).status == .dictation(.init(phase)))
        }
    }

    /// A notice can show while the next dictation is in flight: that one is live, so the menu keeps the notice.
    @Test func aNoticeOverADictationInFlightIsNoYield() {
        let state = DictationState(.transcribing, notice: .failed(DictationID()))
        #expect(Self.view(state, Facts(isYielding: true)).status == .dictation(state))
    }

    /// The history database did not open: the menu says so over the yield and any dictation.
    @Test func theLaunchIssueWinsOverTheYield() {
        var shell = ShellStatus()
        shell.isHistoryUnavailable = true
        #expect(shell.view(Facts(isYielding: true)).status == .historyUnavailable)
        _ = shell.dictationChanged(Self.listening)
        #expect(shell.view(Facts()).status == .historyUnavailable)
    }

    // MARK: Queue reads

    /// 69130e3: a dictation writes the history two or three times; the menu reads its counts at most twice for such a
    /// burst: one read runs, and one more when a write came during it.
    private enum QueueStep {
        case request
        case readEnds
    }

    /// Each step in turn from a fresh shell: whether a request starts a read, or a read that ends starts another.
    private static func reads(_ steps: [QueueStep]) -> [Bool] {
        var shell = ShellStatus()
        return steps.map { step in
            switch step {
            case .request: shell.queueReadRequested()
            case .readEnds: shell.queueRead(.init())
            }
        }
    }

    @Test func aBurstOfWritesReadsTheQueuesTwiceAtMost() {
        let steps: [QueueStep] = [.request, .request, .request, .readEnds, .readEnds, .request]
        #expect(Self.reads(steps) == [true, false, false, true, false, true])
    }

    @Test func aWriteAfterTheReadStartsANewRead() {
        #expect(Self.reads([.request, .readEnds, .request, .readEnds]) == [true, false, true, false])
    }

    @Test func theLastReadSetsTheWaitingCount() {
        var shell = ShellStatus()
        _ = shell.queueReadRequested()
        _ = shell.queueReadRequested()
        _ = shell.queueRead(.init(waitingCount: 1, recovered: [], hasLastDictation: true, hasRawLastDictation: false))
        _ = shell.queueRead(.init(waitingCount: 3, recovered: [], hasLastDictation: true, hasRawLastDictation: true))
        #expect(shell.queues.waitingCount == 3)
        #expect(shell.queues.hasRawLastDictation)
    }

    /// A recovered text is listed by its first 40 characters, with "…" when it goes on.
    @Test func aRecoveredTextIsListedByItsStart() {
        let short = Self.recovered("Ship it on Friday.")
        let long = Self.recovered(String(repeating: "a", count: 40) + "b")
        let exact = Self.recovered(String(repeating: "c", count: 40))
        let queues = ShellStatus.Queues(
            waitingCount: 0, recovered: [short, long, exact], hasLastDictation: false, hasRawLastDictation: false)
        #expect(
            queues.recovered == [
                .init(id: short.id, title: "Ship it on Friday."),
                .init(id: long.id, title: String(repeating: "a", count: 40) + "…"),
                .init(id: exact.id, title: String(repeating: "c", count: 40)),
            ])
    }

    /// The cleaned text of a cleanup dictation is the one recovered.
    @Test func aRecoveredCleanupIsListedByItsCleanedText() {
        var record = Self.recovered("um ship it")
        record.cleanedText = "Ship it."
        let queues = ShellStatus.Queues(
            waitingCount: 0, recovered: [record], hasLastDictation: false, hasRawLastDictation: false)
        #expect(queues.recovered.map(\.title) == ["Ship it."])
    }

    private static func recovered(_ transcript: String) -> DictationRecord {
        DictationRecord(
            id: DictationID(), createdAt: Date(timeIntervalSince1970: 0),
            audio: RecordedAudio(file: URL(filePath: "/tmp/recovered.flac"), duration: .seconds(1)),
            transcript: transcript,
            status: .recovered, latency: LatencyLog())
    }
}
