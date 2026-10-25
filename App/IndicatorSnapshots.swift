import AppKit
import KotobaCore
import KotobaProviders

// MARK: - Snapshots

extension IndicatorPanel {
    /// One pill to render: a name and what the pill shows.
    private struct Sample {
        let name: String
        let content: PillContent
        /// The bars show silence, not speech.
        var isSilent = false
    }

    /// OpenRouter has the longest name of the providers, so its words are the widest; only Azure has an endpoint.
    private static let context = StatusContext(provider: .openRouter)
    private static let azure = StatusContext(provider: .azure)

    /// The pill for `state`, as the panel maps it.
    private static func sample(
        _ name: String, _ state: DictationState, context: StatusContext = context,
        visibility: IndicatorVisibility = .whileDictating
    ) -> Sample? {
        // Any instant: the render counts from its own (`timedNow`).
        content(for: state, context: context, visibility: visibility, timedFrom: .now).map {
            Sample(name: name, content: $0, isSilent: state.phase.isSilentRecording)
        }
    }

    /// Every look the owner sees: each phase and notice through the panel's own mapping, the hover, and the App's
    /// notices. A look with no words renders at the bottom and at a side edge (vertical there); a look with words
    /// looks the same at every anchor, so it renders once. The run fails on content longer than the pill, cut-off
    /// words, words in a live pill, a second glass view, a VoiceOver problem, and any animation at idle.
    static func snapshots() -> [Snapshot] {
        samples.flatMap { sample in
            let anchors: [IndicatorAnchor] =
                sample.content.look.hasWords ? [.bottomCenter] : [.bottomCenter, .left]
            return anchors.map { anchor in
                var snapshot = Snapshot(name: "pill-\(sample.name)-\(anchor.rawValue)") {
                    pill(showing: sample, at: anchor)
                } check: { view in
                    guard let pill = view as? PillView else { return nil }
                    return problem(of: pill, named: sample.name)
                }
                // The pill floats over other apps, so its glass shows over the fixed desktop.
                snapshot.floatsOverDesktop = true
                return snapshot
            }
        }
    }

    /// The pill's main looks for the README and the site (`make readme-images`): recording, transcribing, done and a
    /// notice with a button, each alone and all four in one column, on the showcase stage.
    static func showcaseSnapshots() -> [Snapshot] {
        let looks = [
            sample("recording", .init(.recording(isLong: false))), sample("transcribing", .init(.transcribing)),
            sample("done", .init(.idle, isPasted: true)),
            Sample(name: "learned", content: PillContent(.learned("Kubernetes", id: UUID()))),
        ].compactMap(\.self)
        return (looks.map { [$0] } + [looks]).map { shown in
            let name = shown.count == 1 ? "showcase-pill-\(shown[0].name)" : "showcase-pills"
            var snapshot = Snapshot(name: name) {
                Showcase.pillStage(shown.map { pill(showing: $0, at: .bottomCenter) })
            } check: { stage in
                stage.subviews.lazy.compactMap { ($0 as? PillView).flatMap { problem(of: $0, named: name) } }.first
            }
            snapshot.isOnStage = true
            snapshot.scale = 2
            return snapshot
        }
    }

    private static var samples: [Sample] {
        let id = DictationID()
        var silent = context
        // A long built-in mic name, the widest help tag.
        silent.microphoneName = "MacBook Pro Microphone"
        let denied = StatusContext(provider: .azure, microphone: .denied)
        let secure = StatusContext(provider: .azure, isSecureInputOn: true)
        let states: [Sample?] = [
            sample("idle", .idle, visibility: .always),
            // A development build beside the release app: the bar starts nothing, and VoiceOver says why.
            sample(
                "idle-yielding", .idle, context: StatusContext(provider: .azure, isYielding: true),
                visibility: .always),
            sample("hands-free", .init(.recording(isLong: false))),
            sample("hands-free-cleanup", .init(.recording(isLong: false, isCleaned: true))),
            sample("push-to-talk", .init(.recording(isLong: false, isPushToTalk: true))),
            sample("push-to-talk-cleanup", .init(.recording(isLong: false, isCleaned: true, isPushToTalk: true))),
            sample("silent", .init(.recording(isLong: false, isSilent: true, isPushToTalk: true)), context: silent),
            sample("silent-hands-free", .init(.recording(isLong: false, isSilent: true)), context: silent),
            sample(
                "silent-mic-off", .init(.recording(isLong: false, isSilent: true, isPushToTalk: true)),
                context: denied),
            sample("silent-mic-off-hands-free", .init(.recording(isLong: false, isSilent: true)), context: denied),
            sample("secure-input", .init(.recording(isLong: false, isPushToTalk: true)), context: secure),
            sample("secure-input-hands-free", .init(.recording(isLong: false)), context: secure),
            sample("timer", .init(.recording(isLong: true, isPushToTalk: true))),
            sample("timer-hands-free", .init(.recording(isLong: true))),
            sample("transcribing", .init(.transcribing)),
            sample("cleaning", .init(.cleaning)),
            sample("rewriting", .init(.polishing)),
            sample("done", .init(.idle, isPasted: true)),
            sample("undo", .init(.undoable)),
        ]
        return states.compactMap(\.self) + noticeSamples(id)
            + [
                Sample(
                    name: "hover", content: PillContent(look: .hover(keys: ["⌃", "⌥", "⌘"]), click: .startsDictation)),
                // Auto-learn's notice; the longest word that fits.
                Sample(name: "learned", content: PillContent(.learned("Kubernetes", id: UUID()))),
                // A development build beside the release app.
                Sample(name: "yielding", content: PillContent(.yieldsToRelease)),
            ]
    }

    /// Each notice, once for each wording. The switch has no default, so a new notice does not compile until it has a
    /// sample here.
    private static func noticeSamples(_ id: DictationID) -> [Sample] {
        sampleNotices(id).flatMap { notice -> [Sample?] in
            switch notice {
            case .needsSetup, .hostNotFound:
                setupSamples(id)
            case .rejected:
                [RejectReason.emptyTranscript, .audioMissing, .other].map {
                    sample("rejected-\($0.rawValue)", .init(.idle, notice: .rejected(id, $0)))
                }
            case .copied:
                [
                    sample("copied", .init(.idle, notice: notice)),
                    sample(
                        "copied-no-accessibility", .init(.idle, notice: notice),
                        context: StatusContext(provider: .azure, isPasteAllowed: false)),
                ]
            // No mic, and the same press with Microphone access off.
            case .captureFailed, .bluetoothMicNotListed:
                [
                    sample(snapshotName(of: notice), .init(.idle, notice: notice)),
                    sample(
                        snapshotName(of: notice) + "-denied", .init(.idle, notice: notice),
                        context: StatusContext(provider: .azure, microphone: .denied)),
                ]
            // Named after the case.
            case .failed, .timedOut, .connectionBlocked, .retriesUsedUp, .cleanupFailed, .cleanupTooSlow,
                .returnSkipped, .recovered, .nothingRecorded, .clipboardNotKept:
                [sample(snapshotName(of: notice), .init(.idle, notice: notice))]
            case .audioNotSaved:
                [AudioLoss.diskFull, .other].map {
                    sample("audioNotSaved-\($0)", .init(.idle, notice: .audioNotSaved($0)))
                }
            case .audioCut(let id, _):
                [AudioLoss.diskFull, .other].map { sample("audioCut-\($0)", .init(.idle, notice: .audioCut(id, $0))) }
            case .polished(let id, _):
                [
                    sample("polished", .init(.idle, notice: .polished(id, isReplaced: true))),
                    sample("polished-copied", .init(.idle, notice: .polished(id, isReplaced: false))),
                ]
            case .polishFailed:
                [PolishFailure.nothingToPolish, .cutOff, .tooSlow, .needsSetup(.key), .needsSetup(.credit), .failed].map
                {
                    sample("polishFailed-\(snapshotName(of: $0))", .init(.idle, notice: .polishFailed($0)))
                }
            }
        }
        .compactMap(\.self)
    }

    /// One of each notice; `noticeSamples` draws each wording of it.
    private static func sampleNotices(_ id: DictationID) -> [DictationNotice] {
        [
            .failed(id), .timedOut(id), .connectionBlocked(id), .hostNotFound(id, host: "x"), .retriesUsedUp(id),
            .rejected(id, .other),
            .needsSetup(id, .key), .cleanupFailed(id), .cleanupTooSlow(id), .returnSkipped(id), .copied(id),
            .recovered(id), .captureFailed, .bluetoothMicNotListed("Alex’s AirPods Pro"), .nothingRecorded,
            .polishFailed(.failed),
            .audioNotSaved(.diskFull), .audioCut(id, .diskFull), .clipboardNotKept(id), .polished(id, isReplaced: true),
        ]
    }

    /// What the route needs from the owner, and an endpoint whose host does not resolve: named by its first label when
    /// that fits, else not named.
    private static func setupSamples(_ id: DictationID) -> [Sample?] {
        [
            sample("needs-key", .init(.idle, notice: .needsSetup(id, .key))),
            sample("needs-endpoint", .init(.idle, notice: .needsSetup(id, .endpoint)), context: azure),
            sample("needs-credit", .init(.idle, notice: .needsSetup(id, .credit))),
            sample(
                "hostNotFound-label",
                .init(.idle, notice: .hostNotFound(id, host: "kotoba-asr.cognitiveservices.azure.com")),
                context: azure),
            sample(
                "hostNotFound-unnamed",
                .init(.idle, notice: .hostNotFound(id, host: "my-speech-resource.cognitiveservices.azure.com")),
                context: azure),
        ]
    }

    /// A notice named after its case: "captureFailed", "bluetoothMicNotListed".
    private static func snapshotName(of notice: DictationNotice) -> String {
        String("\(notice)".prefix { $0 != "(" })
    }

    private static func snapshotName(of failure: PolishFailure) -> String {
        switch failure {
        case .nothingToPolish: "nothingToPolish"
        case .cutOff: "cutOff"
        case .tooSlow: "tooSlow"
        case .needsSetup(let item): "needs-\(item.rawValue)"
        case .failed: "failed"
        }
    }

    /// The pill showing `sample` at `anchor`, in a view the size of its capsule (at least as thick as the capsule), after
    /// half a second of speech levels, so the bars show their weights at a speaking level, not one flat row.
    private static func pill(showing sample: Sample, at anchor: IndicatorAnchor) -> PillView {
        let pill = PillView(frame: .zero)
        pill.anchor = anchor
        pill.isClickable = sample.content.click != nil
        pill.toolTip = sample.content.toolTip
        pill.look = timedNow(sample.content.look)
        for level in [0.3, 0.6, 0.9, 0.7, 0.8] where !sample.content.look.isProcessing {
            pill.level = sample.isSilent ? 0 : level
        }
        let size = pill.shapeSize
        pill.setFrameSize(
            NSSize(width: max(size.width, PillGeometry.height), height: max(size.height, PillGeometry.height)))
        return pill
    }

    /// The recording's time counted from 10 minutes before the render, so every image reads 10:00.
    private static func timedNow(_ look: PillLook) -> PillLook {
        guard case .recording(var recording) = look, recording.timedFrom != nil else { return look }
        recording.timedFrom = .now - .seconds(600)
        return .recording(recording)
    }

    /// What is wrong with the pill as drawn, or nil.
    private static func problem(of pill: PillView, named name: String) -> String? {
        // One shape: a capsule, the idle bar, or the check's circle; no other look is a circle or a dot (owner QA 4, U3).
        if pill.shapeSize.width == pill.shapeSize.height, pill.look != .done {
            return "the pill \(name) is a circle; only the check is"
        }
        if pill.isTooLong { return "the content of \(name) needs more than the longest pill" }
        if pill.isTextTruncated { return "the pill words in \(name) are cut off" }
        if pill.isOverflowing { return "the content of \(name) is longer than its capsule" }
        if pill.isLive, !pill.shownWords.isEmpty {
            return "the live pill \(name) shows the words \(pill.shownWords); a live phase shows its shape only"
        }
        let glassCount = glassViews(in: pill)
        if glassCount != 1 { return "the pill \(name) has \(glassCount) glass views, not one: no glass on glass" }
        return accessibilityProblem(of: pill) ?? (pill.look == .idle ? idleCostProblem() : nil)
            ?? reshowProblem(of: pill.look)
    }

    private static func glassViews(in view: NSView) -> Int {
        (view is NSGlassEffectView ? 1 : 0) + view.subviews.map(glassViews).reduce(0, +)
    }

    /// What VoiceOver gets, or nil when it is right: the pill's label, and each button the look shows as a child that a
    /// press runs; the idle bar with a click is a button that a press clicks.
    private static func accessibilityProblem(of pill: PillView) -> String? {
        guard let label = pill.accessibilityLabel(), !label.isEmpty else { return "the pill has no VoiceOver label" }
        let buttons = (pill.accessibilityChildren() ?? []).compactMap { $0 as? PillButtonHost }
        let labels = buttons.map { $0.accessibilityLabel() ?? "" }
        guard labels == pill.look.buttonLabels else {
            return "VoiceOver gets the buttons \(labels), not \(pill.look.buttonLabels)"
        }
        var pressed: [PillView.Action] = []
        pill.onAction = { pressed.append($0) }
        for button in buttons where !button.accessibilityPerformPress() {
            return "a VoiceOver press on \(button.accessibilityLabel() ?? "") does nothing"
        }
        if pill.accessibilityRole() == .button, !pill.accessibilityPerformPress() {
            return "a VoiceOver press on the idle pill does not click it"
        }
        let expected = buttons.count + (pill.accessibilityRole() == .button ? 1 : 0)
        return pressed.count == expected ? nil : "VoiceOver presses ran \(pressed.count) actions, not \(expected)"
    }

    /// No work at idle: the idle bar has no animation, also after the loading dots and a check, and the loading dots
    /// run while text is on its way. Layer animations are the only clock the pill has at idle (no timer, no display
    /// link).
    private static func idleCostProblem() -> String? {
        let pill = PillView(frame: .zero)
        if !pill.animatedLayers.isEmpty { return "the idle pill animates \(pill.animatedLayers.count) layers" }
        pill.look = .processing(.transcribing)
        // Offscreen only loops run: each dot's and the light's two spots, or with Reduce Motion the rim's breath.
        let loops = PillView.reducesMotion ? 1 : PillBars.count + 2
        guard pill.animatedLayers.count == loops else {
            return "the loading look animates \(pill.animatedLayers.count) layers, not \(loops)"
        }
        pill.look = .done
        pill.look = .idle
        return pill.animatedLayers.isEmpty
            ? nil : "after the loading look the idle pill animates \(pill.animatedLayers.count) layers"
    }
}
