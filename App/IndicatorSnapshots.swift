import AppKit
import KotobaCore
import KotobaProviders

// MARK: - Snapshots

extension IndicatorPanel {
    /// One pill to render: a state with its context.
    private struct SnapshotRow {
        let name: String
        let state: DictationState
        // Azure has the longest name, so its texts are the widest.
        var context = StatusContext(provider: .azure)
        /// The mic level the meter shows.
        var level = 0.6

        init(
            name: String, _ phase: DictationPhase, context: StatusContext = .init(provider: .azure), level: Double = 0.6
        ) {
            self.name = name
            state = DictationState(phase)
            self.context = context
            self.level = level
        }

        init(name: String, _ notice: DictationNotice, context: StatusContext = .init(provider: .azure)) {
            self.name = name
            state = DictationState(.idle, notice: notice)
            self.context = context
        }
    }

    /// Every state the owner reads, plus the dragged pill. A compact pill renders at the bottom and at an edge
    /// (vertical there); a pill with text looks the same at every anchor, so it renders once. The run fails
    /// when a pill's text is cut off.
    static func snapshots() -> [Snapshot] {
        let id = DictationID()
        let phases: [DictationPhase] = [
            .idle, .recording(isLong: false), .transcribing, .cleaning, .undoable, .polishing,
        ]
        let notices: [DictationNotice] = [
            .failed(id), .timedOut(id), .connectionBlocked(id), .hostNotFound(id, host: "x"), .rejected(id, .other),
            .needsSetup(id, .key), .cleanupFailed(id), .cleanupTooSlow(id), .returnSkipped(id), .copied(id),
            .recovered(id), .captureFailed, .nothingRecorded, .audioNotSaved(.diskFull), .audioCut(id, .diskFull),
            .clipboardNotKept(id), .polished(id, isReplaced: true), .polishFailed(.failed),
        ]
        var snapshots = [
            Snapshot(name: "indicator-drag") { PillStandIn(content: .init(), anchor: nil) },
            Snapshot(name: "indicator-idle-bottomCenter") {
                PillStandIn(content: .idle(click: .startsDictation), anchor: .bottomCenter)
            } check: { view in
                (view as? PillStandIn).flatMap { accessibilityProblem(of: $0.pill, content: $0.pill.content) }
            },
        ]
        var contents = (phases.flatMap(rows(for:)) + notices.flatMap(rows(for:))).compactMap { row in
            content(for: row.state, context: row.context, visibility: .whileDictating).map { (row.name, $0, row.level) }
        }
        // Auto-learn's notice; the longest word that fits.
        contents.append(("learned", .init(.learned("Kubernetes", id: UUID())), 0.6))
        // A development build beside the release app.
        contents.append(("yielding", .init(.yieldsToRelease), 0.6))
        for (name, content, level) in contents {
            let anchors: [IndicatorAnchor] = content.isCompact ? [.bottomCenter, .left] : [.bottomCenter]
            for anchor in anchors {
                snapshots.append(
                    Snapshot(name: "indicator-\(name)-\(anchor.rawValue)") {
                        PillStandIn(content: content, anchor: anchor, level: level)
                    } check: { view in
                        guard let pill = (view as? PillStandIn)?.pill else { return nil }
                        if pill.isTextTruncated { return "the pill text \"\(content.text)\" is cut off" }
                        return accessibilityProblem(of: pill, content: content)
                    })
            }
        }
        return snapshots
    }

    /// What VoiceOver gets from the pill, or nil when it is right: the pill's click as one button with its label, and
    /// the action's button beside it, not inside; a press on each runs the same path as a click.
    private static func accessibilityProblem(of pill: IndicatorPillView, content: IndicatorPillView.Content) -> String?
    {
        let children = pill.accessibilityChildren() ?? []
        let buttons = children.compactMap { $0 as? NSAccessibilityProtocol }.filter {
            $0.accessibilityRole() == .button
        }
        let label = content.click.map(StatusText.pillClickLabel)
        let taps = buttons.filter { $0 is PillTapTarget }
        guard taps.map({ $0.accessibilityLabel() }) == (label.map { [$0] } ?? []) else {
            return "VoiceOver gets \(taps.count) click buttons, not one \"\(label ?? "none")\""
        }
        var clicks = 0
        pill.onClick = { clicks += 1 }
        if let tap = taps.first, !tap.accessibilityPerformPress() || clicks != 1 {
            return "a VoiceOver press on \"\(label ?? "")\" does not click the pill"
        }
        // VoiceOver's pointer at the pill's leading end, over the dot and the text.
        let frame = NSAccessibility.screenRect(fromView: pill, rect: pill.bounds)
        let leading = NSPoint(x: frame.minX + frame.height / 2, y: frame.midY)
        if let tap = taps.first, pill.accessibilityHitTest(leading) as AnyObject !== tap as AnyObject {
            return "VoiceOver's pointer on the pill does not reach \"\(label ?? "")\""
        }
        guard let action = content.action, pill.layout == .horizontal else { return nil }
        guard let button = buttons.first(where: { $0 is NSView && $0.accessibilityLabel() == action.title }),
            let view = button as? NSView
        else {
            return "VoiceOver gets no \"\(action.title)\" button beside the pill's click"
        }
        let buttonFrame = NSAccessibility.screenRect(fromView: view, rect: view.bounds)
        if pill.accessibilityHitTest(NSPoint(x: buttonFrame.midX, y: buttonFrame.midY)) as AnyObject !== view {
            return "VoiceOver's pointer on \"\(action.title)\" does not reach it"
        }
        var pressed: PillAction?
        pill.onAction = { pressed = $0 }
        return button.accessibilityPerformPress() && pressed == action
            ? nil : "a VoiceOver press on \"\(action.title)\" does not run its action"
    }

    /// A long built-in mic name, the widest "No sound" text.
    private static var silent: StatusContext {
        var context = StatusContext(provider: .azure)
        context.microphoneName = "MacBook Pro Microphone"
        return context
    }

    /// The rows for one phase. The switch has no default, so a new phase does not compile until it has rows here;
    /// give it a sample in `snapshots()` too.
    private static func rows(for phase: DictationPhase) -> [SnapshotRow] {
        switch phase {
        case .idle: []
        case .recording: recordingRows
        case .transcribing: [SnapshotRow(name: "transcribing", phase)]
        case .cleaning: [SnapshotRow(name: "cleaning", phase)]
        case .undoable: [SnapshotRow(name: "undoable", phase)]
        case .polishing: [SnapshotRow(name: "polishing", phase)]
        }
    }

    /// The rows for one notice, as `rows(for:)` for a phase.
    private static func rows(for notice: DictationNotice) -> [SnapshotRow] {
        switch notice {
        case .needsSetup(let id, _), .hostNotFound(let id, _):
            setupRows(of: id)
        case .rejected(let id, _):
            [RejectReason.emptyTranscript, .audioMissing, .other].map {
                SnapshotRow(name: "rejected-\($0.rawValue)", .rejected(id, $0))
            }
        case .copied:
            [
                SnapshotRow(name: "copied", notice),
                SnapshotRow(
                    name: "copied-no-accessibility", notice,
                    context: StatusContext(provider: .azure, isPasteAllowed: false)),
            ]
        case .captureFailed:
            [
                SnapshotRow(name: "captureFailed", notice),
                SnapshotRow(
                    name: "captureFailed-denied", notice,
                    context: StatusContext(provider: .azure, microphone: .denied)),
            ]
        // Named after the case, as its file always was.
        case .failed, .timedOut, .connectionBlocked, .cleanupFailed, .cleanupTooSlow, .returnSkipped, .recovered,
            .nothingRecorded, .clipboardNotKept:
            [SnapshotRow(name: String("\(notice)".prefix { $0 != "(" }), notice)]
        case .audioNotSaved, .audioCut: lossRows(of: notice)
        case .polished, .polishFailed:
            polishRows(for: notice)
        }
    }

    /// Polish's notices: the replaced and the new-text outcome, and each failure.
    private static func polishRows(for notice: DictationNotice) -> [SnapshotRow] {
        switch notice {
        case .polished(let id, _):
            [
                SnapshotRow(name: "polished", .polished(id, isReplaced: true)),
                SnapshotRow(name: "polished-copied", .polished(id, isReplaced: false)),
            ]
        default:
            [PolishFailure.nothingToPolish, .cutOff, .tooSlow, .needsSetup(.key), .needsSetup(.credit), .failed].map {
                SnapshotRow(name: "polishFailed-\(Self.snapshotName(of: $0))", .polishFailed($0))
            }
        }
    }

    /// The recording pill: plain, long, under Secure Input, silent (and silent with Microphone access off), cleaned up.
    private static var recordingRows: [SnapshotRow] {
        [
            SnapshotRow(name: "recording", .recording(isLong: false)),
            SnapshotRow(name: "recording-long", .recording(isLong: true)),
            SnapshotRow(
                name: "secure-input", .recording(isLong: false),
                context: StatusContext(provider: .azure, isSecureInputOn: true)),
            SnapshotRow(name: "recording-silent", .recording(isLong: false, isSilent: true), context: silent, level: 0),
            SnapshotRow(
                name: "recording-silent-denied", .recording(isLong: false, isSilent: true),
                context: StatusContext(provider: .azure, microphone: .denied), level: 0),
            SnapshotRow(name: "recording-cleaned", .recording(isLong: false, isCleaned: true)),
        ]
    }

    /// What the route needs from the owner, and an endpoint whose host does not resolve: named by its first label when
    /// that fits, else not named.
    private static func setupRows(of id: DictationID) -> [SnapshotRow] {
        [
            SnapshotRow(name: "needs-key", .needsSetup(id, .key)),
            SnapshotRow(name: "needs-endpoint", .needsSetup(id, .endpoint)),
            SnapshotRow(name: "needs-credit", .needsSetup(id, .credit)),
            SnapshotRow(name: "hostNotFound-label", .hostNotFound(id, host: "kotoba-asr.cognitiveservices.azure.com")),
            SnapshotRow(
                name: "hostNotFound-unnamed",
                .hostNotFound(id, host: "my-speech-resource.cognitiveservices.azure.com")),
        ]
    }

    /// A lost-audio notice once for each cause: only a full disk says "Disk full?".
    private static func lossRows(of notice: DictationNotice) -> [SnapshotRow] {
        [AudioLoss.diskFull, .other].compactMap { loss in
            switch notice {
            case .audioNotSaved: SnapshotRow(name: "audioNotSaved-\(loss)", .audioNotSaved(loss))
            case .audioCut(let id, _): SnapshotRow(name: "audioCut-\(loss)", .audioCut(id, loss))
            default: nil
            }
        }
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
}

/// The pill over a capsule in the window color, since its glass does not render offscreen. A pill with a timer
/// shows its bar held at 60 %.
private final class PillStandIn: NSView {
    let pill = IndicatorPillView(frame: .zero)

    /// A nil anchor shows the dragged pill.
    init(content: IndicatorPillView.Content, anchor: IndicatorAnchor?, level: Double = 0.6) {
        pill.content = content
        pill.level = level
        if let timer = content.timer {
            let now = ContinuousClock.now
            var countdown = Countdown(duration: timer.duration, startingAt: now - timer.duration * 0.4)
            countdown.hold(at: now)
            pill.countdown = countdown
        }
        let frame: ScreenRect
        if content.isRound, let anchor {
            pill.layout = .round
            frame = IndicatorPlacement.roundFrame(at: anchor, in: ScreenRect(x: 0, y: 0, width: 1512, height: 945))
        } else if let anchor {
            pill.layout =
                IndicatorPlacement.isVertical(at: anchor, isCompact: content.isCompact) ? .vertical : .horizontal
            // Only the size matters here, so any visible frame does.
            frame = IndicatorPlacement.frame(
                at: anchor, isCompact: content.isCompact, contentWidth: pill.fittingWidth,
                in: ScreenRect(x: 0, y: 0, width: 1512, height: 945))
        } else {
            pill.layout = .round
            frame = IndicatorPlacement.dragFrame(centeredAt: ScreenPoint(x: 0, y: 0))
        }
        super.init(frame: NSRect(x: 0, y: 0, width: frame.width, height: frame.height))
        pill.frame = bounds
        addSubview(pill)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("PillStandIn is built in code")
    }

    override func draw(_ dirtyRect: NSRect) {
        let radius = IndicatorPlacement.cornerRadius
        let capsule = NSBezierPath(roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5), xRadius: radius, yRadius: radius)
        NSColor.controlBackgroundColor.setFill()
        capsule.fill()
        NSColor.separatorColor.setStroke()
        capsule.stroke()
    }
}
