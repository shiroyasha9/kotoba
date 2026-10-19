import Foundation

/// The segments of one live recording (`CaptureEvent.segment`), each sent while it records on a route that sends the
/// upload copy, and the recording's answer at the stop (docs/research/latency-pass-2.md section 7): the segments'
/// texts and the copy after the last cut joined, so the stop waits only for the last one. The whole recording goes as
/// one request, as before segments, when it was not cut, or when a segment failed, timed out or was not sent: the text
/// never comes from part of the audio. A dictation's entry in `LiveDictations` holds one; every end takes it.
struct SegmentUpload: Sendable {
    /// How the text of a recording came, for the latency line.
    enum Use: Sendable, Equatable {
        /// One request for the whole recording: no cut.
        case one
        /// `count` requests joined: the segments, and the copy after the last cut (`tail`, its length).
        case joined(count: Int, tail: Duration)
        /// The whole recording, as one of its `count` segments failed, timed out or was not sent.
        case whole(count: Int)
    }

    /// The segments' answers, in recording order.
    private var answers: [Task<Transcript, any Error>] = []
    /// A segment closed that was not sent (the route sends the FLAC): the stop sends the whole recording.
    private var isBroken = false

    /// Nothing to cancel or bill at an end.
    var isEmpty: Bool { answers.isEmpty && !isBroken }

    /// Sends `segment` now as its own request (`settings`' language and keyterms), unless the route sends the FLAC or
    /// an earlier segment was not sent; its answer waits for the stop, which bounds its time as any request's
    /// (`Settings.transcriptionTimeout(for:)`, from the send). Its file goes when its request ends, or now when it is
    /// not sent. True when it went.
    @discardableResult
    mutating func send(
        _ segment: UploadSegment, settings: DictationPipeline.Settings, through steps: TranscriptionSteps
    ) -> Bool {
        guard steps.provider.sendsUploadCopy, !isBroken, segment.index == answers.count else {
            isBroken = true
            AudioCapture.removeUploadCopy(segment.file)
            return false
        }
        let copy = RecordedAudio(file: segment.file, duration: segment.duration, upload: segment.file)
        let request = settings.request(for: copy, at: steps.clock.date)
        // Its error reaches the stop through `joined`.
        let answer = Task {
            defer { AudioCapture.removeUploadCopy(segment.file) }
            return try await steps.answer(to: request)
        }
        answers.append(answer)
        return true
    }

    /// The answer for `audio` at its stop, from `request` (the whole recording's: its language, keyterms and model go
    /// with the last segment too). Not cut: one request, as before segments. Cut: the copy after the last cut goes now,
    /// beside the segments still on their way, and their texts join in order with one space, as the model wrote them;
    /// one speech answer with the costs added up and the recording's length. At the first failure the others are
    /// cancelled and the whole recording goes as the FLAC; the answers not used are billed to `id` with no audio and
    /// no words, so minutes and words stay what the owner dictated.
    func answer(
        to request: TranscriptionRequest, of audio: RecordedAudio, through steps: TranscriptionSteps,
        billingTo id: DictationID, app: DictationApp?
    ) async throws -> (Transcript, Use) {
        var whole = request
        guard audio.uploadStart > .zero || !isEmpty else { return (try await steps.answer(to: whole), .one) }
        // After a cut the copy holds only the audio after it: the whole recording goes as the FLAC.
        whole.upload = nil
        guard !isBroken, !answers.isEmpty, let upload = audio.upload, audio.uploadStart > .zero,
            steps.provider.sendsUploadCopy
        else {
            Self.settle(answers, through: steps, billingTo: id, app: app)
            return (try await steps.answer(to: whole), .whole(count: answers.count))
        }
        var tail = request
        (tail.audio, tail.upload, tail.duration) = (upload, upload, audio.duration - audio.uploadStart)
        let last = Task { [tail] in try await steps.answer(to: tail) }
        let parts = answers + [last]
        if let joined = await Self.joined(parts, duration: audio.duration) {
            return (joined, .joined(count: parts.count, tail: tail.duration))
        }
        Self.settle(parts, through: steps, billingTo: id, app: app)
        return (try await steps.answer(to: whole), .whole(count: parts.count))
    }

    /// The dictation `id` ends with no send (cancelled, dropped, or kept at quit): the requests still on their way
    /// are cancelled, and the ones that answered are billed.
    func cancel(through steps: TranscriptionSteps, billingTo id: DictationID, app: DictationApp?) {
        Self.settle(answers, through: steps, billingTo: id, app: app)
    }

    /// The parts' answers as one once all came: the texts in order with one space, the costs added up, the
    /// recording's `duration`, and the model and network moments of the last part (the copy after the last cut). Nil
    /// at the first failure, which cancels the others.
    private static func joined(_ parts: [Task<Transcript, any Error>], duration: Duration) async -> Transcript? {
        let answers = await withTaskGroup(of: (Int, Transcript?).self) { group -> [Transcript]? in
            for (index, part) in parts.enumerated() {
                // Any failure sends the whole recording, so which one it was does not matter here; each part logs its own.
                group.addTask { (index, try? await part.value) }
            }
            var answers = [Transcript?](repeating: nil, count: parts.count)
            for await (index, answer) in group {
                guard let answer else {
                    // Awaiting a task's value does not follow the group's cancellation: the parts end here.
                    for part in parts { part.cancel() }
                    return nil
                }
                answers[index] = answer
            }
            return answers.compactMap(\.self)
        }
        guard let answers, let last = answers.last else { return nil }
        let texts = answers.map { $0.text.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        let costs = answers.compactMap(\.usage.cost)
        let cost =
            costs.isEmpty
            ? nil
            : Cost(
                usd: costs.reduce(0) { $0 + $1.usd },
                isEstimated: costs.count < answers.count || costs.contains(where: \.isEstimated))
        return Transcript(
            text: texts.joined(separator: " "), usage: TranscriptionUsage(audio: duration, cost: cost),
            model: last.model, network: last.network)
    }

    /// Requests whose text is not used: the ones still on their way are cancelled, and each that answered is billed
    /// with no audio and no words. Each on its own, so one that answered goes to the ledger at once, also at quit,
    /// and does not wait for a cancelled one to end.
    private static func settle(
        _ unused: [Task<Transcript, any Error>], through steps: TranscriptionSteps, billingTo id: DictationID,
        app: DictationApp?
    ) {
        for request in unused {
            request.cancel()
            steps.work.bill { [store = steps.store, clock = steps.clock] in
                guard case .success(let answer) = await request.result else { return }
                do {
                    try await store.addUsage([
                        UsageEntry(
                            time: clock.date, dictation: id, kind: .speech, model: answer.model, deliveredWords: 0,
                            cost: answer.usage.cost, app: app)
                    ])
                } catch {
                    Log.pipeline.error("Segment of \(id.rawValue): cannot bill it: \(error)")
                }
            }
        }
    }
}

// MARK: - The pipeline's side

extension DictationPipeline {
    /// The capture closed `segment` of the dictation `id` at a pause: it goes now (`SegmentUpload.send`). A segment
    /// request warms the route as a primer does, so the next primer waits `Settings.primerInterval` from it.
    func segmentClosed(_ segment: UploadSegment, of id: DictationID) {
        let isSent = live.withSegments(of: id) { [settings, steps = delivery.steps] in
            $0.send(segment, settings: settings, through: steps)
        }
        guard let isSent else {
            // The dictation ended: nothing sends its segments.
            AudioCapture.removeUploadCopy(segment.file)
            return
        }
        guard isSent, recording?.id == id, ports.provider.hasPrimer else { return }
        primedAt = ports.clock.now
        recording?.primerTimer?.cancel()
        recording?.primerTimer = nil
        armPrimer(for: id)
    }

    /// The dictation `id` ends with no send: its segments go (`SegmentUpload.cancel`). Every end of a dictation calls
    /// it or sends them first; `LiveDictations.end` checks.
    func dropSegments(of id: DictationID) {
        let segments = live.takeSegments(of: id)
        guard !segments.isEmpty else { return }
        segments.cancel(through: delivery.steps, billingTo: id, app: ports.frontApp()?.app)
    }
}
