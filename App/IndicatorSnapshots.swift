import AppKit
import KotobaCore
import KotobaProviders

// MARK: - Snapshots

extension IndicatorPanel {
    /// One pill to render: a name and what the pill shows.
    private struct Sample {
        let name: String
        let content: PillContent
        /// The bars show silence, not the mirrored ripple of a few speech levels.
        var isSilent = false
    }

    /// Azure has the longest name, so its words are the widest.
    private static let context = StatusContext(provider: .azure)

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
                // Under the pointer during a drag: VoiceOver still reads the look under it.
                Sample(name: "dragged", content: PillContent(look: .dragged(.recording(.init(isHandsFree: true))))),
                // Auto-learn's notice; the longest word that fits.
                Sample(name: "learned", content: PillContent(.learned("Kubernetes", id: UUID()))),
                // A development build beside the release app.
                Sample(name: "yielding", content: PillContent(.yieldsToRelease)),
            ]
    }

    /// Each notice, once for each wording. The switch has no default, so a new notice does not compile until it has a
    /// sample here.
    private static func noticeSamples(_ id: DictationID) -> [Sample] {
        let notices: [DictationNotice] = [
            .failed(id), .timedOut(id), .connectionBlocked(id), .hostNotFound(id, host: "x"), .rejected(id, .other),
            .needsSetup(id, .key), .cleanupFailed(id), .cleanupTooSlow(id), .returnSkipped(id), .copied(id),
            .recovered(id), .captureFailed, .nothingRecorded, .audioNotSaved(.diskFull), .audioCut(id, .diskFull),
            .clipboardNotKept(id), .polished(id, isReplaced: true), .polishFailed(.failed),
        ]
        return notices.flatMap { notice -> [Sample?] in
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
            case .captureFailed:
                [
                    sample("captureFailed", .init(.idle, notice: notice)),
                    sample(
                        "captureFailed-denied", .init(.idle, notice: notice),
                        context: StatusContext(provider: .azure, microphone: .denied)),
                ]
            // Named after the case.
            case .failed, .timedOut, .connectionBlocked, .cleanupFailed, .cleanupTooSlow, .returnSkipped, .recovered,
                .nothingRecorded, .clipboardNotKept:
                [sample(String("\(notice)".prefix { $0 != "(" }), .init(.idle, notice: notice))]
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

    /// What the route needs from the owner, and an endpoint whose host does not resolve: named by its first label when
    /// that fits, else not named.
    private static func setupSamples(_ id: DictationID) -> [Sample?] {
        [
            sample("needs-key", .init(.idle, notice: .needsSetup(id, .key))),
            sample("needs-endpoint", .init(.idle, notice: .needsSetup(id, .endpoint))),
            sample("needs-credit", .init(.idle, notice: .needsSetup(id, .credit))),
            sample(
                "hostNotFound-label",
                .init(.idle, notice: .hostNotFound(id, host: "kotoba-asr.cognitiveservices.azure.com"))),
            sample(
                "hostNotFound-unnamed",
                .init(.idle, notice: .hostNotFound(id, host: "my-speech-resource.cognitiveservices.azure.com"))),
        ]
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
    /// a few level events, so the bars show the mirrored ripple, not one flat step.
    private static func pill(showing sample: Sample, at anchor: IndicatorAnchor) -> PillView {
        let pill = PillView(frame: .zero)
        pill.anchor = anchor
        pill.isClickable = sample.content.click != nil
        pill.toolTip = sample.content.toolTip
        pill.look = timedNow(sample.content.look)
        for level in [0.3, 0.9, 0.5, 0.8] where !sample.content.look.isProcessing {
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
        if pill.isTooLong { return "the content of \(name) needs more than the longest pill" }
        if pill.isTextTruncated { return "the pill words in \(name) are cut off" }
        if pill.isOverflowing { return "the content of \(name) is longer than its capsule" }
        if pill.isLive, !pill.shownWords.isEmpty {
            return "the live pill \(name) shows the words \(pill.shownWords); a live phase shows its shape only"
        }
        let glassCount = glassViews(in: pill)
        if glassCount != 1 { return "the pill \(name) has \(glassCount) glass views, not one: no glass on glass" }
        return accessibilityProblem(of: pill) ?? (pill.look == .idle ? idleCostProblem() : nil)
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

    /// No work at idle: the idle bar has no animation, also after a sweep and a check, and the sweep runs while text is
    /// on its way. Layer animations are the only clock the pill has at idle (no timer, no display link).
    private static func idleCostProblem() -> String? {
        let pill = PillView(frame: .zero)
        if !pill.animatedLayers.isEmpty { return "the idle pill animates \(pill.animatedLayers.count) layers" }
        pill.look = .processing(.transcribing)
        guard pill.animatedLayers.count == PillBars.count else {
            return "the sweep animates \(pill.animatedLayers.count) layers, not \(PillBars.count)"
        }
        pill.look = .done
        pill.look = .idle
        return pill.animatedLayers.isEmpty
            ? nil : "after a sweep the idle pill animates \(pill.animatedLayers.count) layers"
    }
}

// MARK: Checks

extension PillView {
    /// Every layer under the pill with a running animation: the idle-cost check wants none at idle.
    var animatedLayers: [CALayer] {
        // A view's layer is also its parent view's sublayer, so each layer counts once.
        var seen = Set<ObjectIdentifier>()
        func walk(_ layer: CALayer) -> [CALayer] {
            guard seen.insert(ObjectIdentifier(layer)).inserted else { return [] }
            let own = (layer.animationKeys() ?? []).isEmpty ? [] : [layer]
            return own + (layer.sublayers ?? []).flatMap(walk)
        }
        func walk(_ view: NSView) -> [CALayer] {
            (view.layer.map(walk) ?? []) + view.subviews.flatMap(walk)
        }
        return walk(self)
    }

    /// The content is longer than the capsule, so an item sits outside it. Valid after layout.
    var isOverflowing: Bool {
        let content = stack.arrangedSubviews.map(\.frame).reduce(NSRect.null) { $0.union($1) }
        return !content.isNull && !stack.bounds.insetBy(dx: -0.5, dy: -0.5).contains(content)
    }

    /// The content needs more than the longest pill, so its words cannot all show.
    var isTooLong: Bool {
        contentLength > PillGeometry.maxLength + 0.5
    }

    /// The words or the time are narrower than their text, so they end in "…" or are cut. Valid after layout.
    var isTextTruncated: Bool {
        stack.arrangedSubviews.contains {
            guard let text = $0 as? NSTextField else { return false }
            return text.intrinsicContentSize.width > text.frame.width + 0.5
        }
    }

    /// A live phase with no words: a recording that shows only its bars and buttons, or the sweep.
    var isLive: Bool {
        switch look {
        case .processing: true
        case .recording(let recording): recording.words == nil && recording.timedFrom == nil
        case .idle, .hover, .done, .message, .dragged: false
        }
    }

    /// The words the pill shows, its time included.
    var shownWords: [String] {
        stack.arrangedSubviews.compactMap { ($0 as? NSTextField)?.stringValue }
    }
}
