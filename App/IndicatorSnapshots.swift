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
    }

    /// Every state the owner reads, plus the dragged pill. A compact pill renders at the bottom and at an edge
    /// (vertical there); a pill with text looks the same at every anchor, so it renders once. The run fails
    /// when a pill's text is cut off.
    static func snapshots() -> [Snapshot] {
        let indicator = IndicatorPanel()
        let id = DictationID()
        let samples: [DictationState] = [
            .idle, .recording(isLong: false), .transcribing, .undoable, .failed(id), .rejected(id, .other),
            .needsSetup(id, .key), .cleanupFailed(id), .copied(id), .recovered(id), .captureFailed,
        ]
        var snapshots = [
            Snapshot(name: "indicator-drag") { PillStandIn(content: .init(), anchor: nil) }
        ]
        for row in samples.flatMap(snapshotRows) {
            guard let content = indicator.content(for: row.state, context: row.context) else { continue }
            let anchors: [IndicatorAnchor] = content.isCompact ? [.bottomCenter, .left] : [.bottomCenter]
            for anchor in anchors {
                snapshots.append(
                    Snapshot(name: "indicator-\(row.name)-\(anchor.rawValue)") {
                        PillStandIn(content: content, anchor: anchor)
                    } check: { view in
                        (view as? PillStandIn)?.pill.isTextTruncated == true
                            ? "the pill text \"\(content.text)\" is cut off" : nil
                    })
            }
        }
        return snapshots
    }

    /// The rows for one state. The switch has no default, so a new `DictationState` case does not compile
    /// until it has rows here; give it a sample in `snapshots()` too.
    private static func snapshotRows(for state: DictationState) -> [SnapshotRow] {
        switch state {
        case .idle:
            []
        case .recording:
            [
                SnapshotRow(name: "recording", state: .recording(isLong: false)),
                SnapshotRow(name: "recording-long", state: .recording(isLong: true)),
                SnapshotRow(
                    name: "secure-input", state: .recording(isLong: false),
                    context: StatusContext(provider: .azure, isSecureInputOn: true)),
            ]
        case .needsSetup(let id, _):
            [
                SnapshotRow(name: "needs-key", state: .needsSetup(id, .key)),
                SnapshotRow(name: "needs-endpoint", state: .needsSetup(id, .endpoint)),
                SnapshotRow(name: "needs-credit", state: .needsSetup(id, .credit)),
            ]
        case .rejected(let id, _):
            [RejectReason.emptyTranscript, .other].map {
                SnapshotRow(name: "rejected-\($0.rawValue)", state: .rejected(id, $0))
            }
        case .copied:
            [
                SnapshotRow(name: "copied", state: state),
                SnapshotRow(
                    name: "copied-no-accessibility", state: state,
                    context: StatusContext(provider: .azure, isPasteAllowed: false)),
            ]
        case .captureFailed:
            [
                SnapshotRow(name: "captureFailed", state: state),
                SnapshotRow(
                    name: "captureFailed-denied", state: state,
                    context: StatusContext(provider: .azure, microphone: .denied)),
            ]
        case .transcribing, .undoable, .failed, .cleanupFailed, .recovered:
            [SnapshotRow(name: snapshotName(of: state), state: state)]
        }
    }

    /// The file name of a state with one row; a case rename does not change it.
    private static func snapshotName(of state: DictationState) -> String {
        switch state {
        case .transcribing: "transcribing"
        case .undoable: "undoable"
        case .failed: "failed"
        case .cleanupFailed: "cleanupFailed"
        case .recovered: "recovered"
        case .idle, .recording, .needsSetup, .rejected, .copied, .captureFailed: "\(state)"
        }
    }
}

/// The pill over a capsule in the window color, since its glass does not render offscreen.
private final class PillStandIn: NSView {
    let pill = IndicatorPillView(frame: .zero)

    /// A nil anchor shows the dragged pill.
    init(content: IndicatorPillView.Content, anchor: IndicatorAnchor?) {
        pill.content = content
        pill.level = 0.6
        let frame: ScreenRect
        if let anchor {
            pill.layout =
                IndicatorPlacement.isVertical(at: anchor, isCompact: content.isCompact) ? .vertical : .horizontal
            // Only the size matters here, so any visible frame does.
            frame = IndicatorPlacement.frame(
                at: anchor, isCompact: content.isCompact, contentWidth: pill.fittingWidth,
                in: ScreenRect(x: 0, y: 0, width: 1512, height: 945))
        } else {
            pill.layout = .drag
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
