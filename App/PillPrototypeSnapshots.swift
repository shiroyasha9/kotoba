import AppKit

// MARK: - Snapshots

extension PillPrototypeView {
    /// The hands-free chord the samples show on hover.
    static let sampleKeys = ["⌃", "⌥", "⌘"]

    /// Every look of the prototype, named as in the gallery, with a sample for each kind of words.
    static let samples: [(name: String, look: PillLook)] = [
        ("idle", .idle),
        ("hover", .hover(keys: sampleKeys)),
        ("push-to-talk", .recording(.init())),
        ("push-to-talk-cleanup", .recording(.init(isCleaned: true))),
        ("hands-free", .recording(.init(isHandsFree: true))),
        ("hands-free-cleanup", .recording(.init(isHandsFree: true, isCleaned: true))),
        ("processing", .processing),
        ("done", .done),
        ("silent", .recording(.init(isSilent: true))),
        ("silent-hands-free", .recording(.init(isHandsFree: true, isSilent: true))),
        ("timer", .recording(.init(elapsed: .seconds(600)))),
        ("timer-hands-free", .recording(.init(isHandsFree: true, elapsed: .seconds(612)))),
        (
            "error-retry",
            .message(.init(text: "Couldn’t reach OpenRouter. Will retry.", isProblem: true, button: "Retry"))
        ),
        ("error-key", .message(.init(text: "Add your OpenRouter key", isProblem: true, button: "Add Key…"))),
        ("error-credit", .message(.init(text: "Add credit at OpenRouter", isProblem: true, button: "Add Credit…"))),
        (
            "error-mic-off",
            .message(.init(text: StatusText.microphoneOff, isProblem: true, button: "Open System Settings…"))
        ),
        ("error-no-mic", .message(.init(text: "No microphone found", isProblem: true, button: "Choose Mic…"))),
        ("undo-cancel", .message(.init(text: "Canceled", button: "Undo"))),
        ("undo-rewrite", .message(.init(text: "Rewritten", button: "Undo"))),
        ("added-word", .message(.init(text: StatusText.learned("Kubernetes"), button: "Undo"))),
    ]

    /// Each look at the bottom, and at a side edge where it stands vertical there, on its glass over the fixed desktop
    /// (the pill floats over other apps). The run fails on cut-off words, on a VoiceOver problem, and on any animation
    /// at idle.
    static func snapshots() -> [Snapshot] {
        samples.flatMap { sample in
            let sides = sample.look.canStandVertical ? [false, true] : [false]
            return sides.map { isAtSideEdge in
                var snapshot = Snapshot(name: "pill-proto-\(sample.name)-\(isAtSideEdge ? "left" : "bottomCenter")") {
                    sampled(sample.look, isAtSideEdge: isAtSideEdge)
                } check: { view in
                    guard let pill = view as? PillPrototypeView else { return nil }
                    if pill.isTextTruncated { return "the pill text in \(sample.name) is cut off" }
                    if pill.isOverflowing { return "the content of \(sample.name) is longer than its capsule" }
                    return accessibilityProblem(of: pill) ?? (sample.look == .idle ? idleCostProblem() : nil)
                }
                snapshot.floatsOverDesktop = true
                return snapshot
            }
        }
    }

    /// The pill showing `look` at its own size, after a few level events, so the bars show the mirrored ripple, not
    /// one flat step.
    private static func sampled(_ look: PillLook, isAtSideEdge: Bool) -> PillPrototypeView {
        let pill = PillPrototypeView()
        pill.hoverKeys = sampleKeys
        pill.isAtSideEdge = isAtSideEdge
        pill.look = look
        let isSilent = if case .recording(let recording) = look { recording.isSilent } else { false }
        for level in [0.3, 0.9, 0.5, 0.8] where look != .processing {
            pill.level = isSilent ? 0 : level
        }
        pill.setFrameSize(pill.shapeSize)
        return pill
    }

    /// What VoiceOver gets, or nil when it is right: the pill's label, and each button the look shows as a child that a
    /// press runs.
    private static func accessibilityProblem(of pill: PillPrototypeView) -> String? {
        guard let label = pill.accessibilityLabel(), !label.isEmpty else { return "the pill has no VoiceOver label" }
        let buttons = (pill.accessibilityChildren() ?? []).compactMap { $0 as? PillFillButtonHost }
        let labels = buttons.map { $0.accessibilityLabel() ?? "" }
        guard labels == pill.look.buttonLabels else {
            return "VoiceOver gets the buttons \(labels), not \(pill.look.buttonLabels)"
        }
        var pressed: [Action] = []
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

    /// No work at idle: the idle bar has no animation, also after a sweep and a check, and the sweep runs while text
    /// is on its way. Layer animations are the only clock the pill has (no timer, no display link).
    private static func idleCostProblem() -> String? {
        let pill = PillPrototypeView(frame: .zero)
        if !pill.animatedLayers.isEmpty { return "the idle pill animates \(pill.animatedLayers.count) layers" }
        pill.look = .processing
        guard pill.animatedLayers.count == PillBars.count else {
            return "the sweep animates \(pill.animatedLayers.count) layers, not \(PillBars.count)"
        }
        pill.look = .done
        pill.look = .idle
        return pill.animatedLayers.isEmpty
            ? nil : "after a sweep the idle pill animates \(pill.animatedLayers.count) layers"
    }
}

extension PillLook {
    /// The buttons the look shows, in order, as VoiceOver reads them.
    var buttonLabels: [String] {
        switch self {
        case .idle, .hover, .processing, .done: []
        case .recording(let recording):
            (recording.isHandsFree && !recording.isSilent ? ["Cancel"] : [])
                + (recording.isSilent ? ["Choose Mic…"] : [])
                + (recording.isHandsFree ? ["Stop"] : [])
        case .message(let message): message.button.map { [$0] } ?? []
        }
    }
}
