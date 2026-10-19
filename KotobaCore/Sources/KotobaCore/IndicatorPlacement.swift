/// Where the recording indicator sits on its screen.
public enum IndicatorAnchor: String, CaseIterable, Sendable {
    /// A horizontal pill just above the Dock or the screen bottom. The default.
    case bottomCenter
    /// Mid-height on the left edge; vertical when the pill shows no text.
    case left
    /// Mid-height on the right edge; vertical when the pill shows no text.
    case right
}

/// What a click on the indicator pill does: the chord tap it stands for.
public enum PillClick: Sendable, Equatable {
    case startsDictation
    case stopsDictation
}

/// A point in AppKit screen coordinates (origin bottom left). KotobaCore cannot import
/// CoreGraphics, so the app converts to and from `NSPoint`.
public struct ScreenPoint: Sendable, Equatable {
    public var x: Double
    public var y: Double

    public init(x: Double, y: Double) {
        self.x = x
        self.y = y
    }

    func distance(to other: Self) -> Double {
        ((other.x - x) * (other.x - x) + (other.y - y) * (other.y - y)).squareRoot()
    }
}

/// A rectangle in AppKit screen coordinates (origin bottom left); the app converts to and from `NSRect`.
public struct ScreenRect: Sendable, Equatable {
    public var x: Double
    public var y: Double
    public var width: Double
    public var height: Double

    public init(x: Double, y: Double, width: Double, height: Double) {
        self.x = x
        self.y = y
        self.width = width
        self.height = height
    }

    public var minX: Double { x }
    public var minY: Double { y }
    public var maxX: Double { x + width }
    public var maxY: Double { y + height }
    var mid: ScreenPoint { ScreenPoint(x: x + width / 2, y: y + height / 2) }

    func overlapArea(with other: Self) -> Double {
        let width = min(maxX, other.maxX) - max(minX, other.minX)
        let height = min(maxY, other.maxY) - max(minY, other.minY)
        return width > 0 && height > 0 ? width * height : 0
    }
}

/// The indicator's placement math: one frame per anchor inside the screen's visible frame (so
/// the pill never sits under the Dock, menu bar or notch), and the anchor nearest a drop point.
public enum IndicatorPlacement {
    /// The pill with text, and every pill at the bottom center, is as wide as its content within these limits.
    static let minWidth = 120.0
    static let maxWidth = 360.0
    static let horizontalHeight = 40.0
    /// Every pill shape is a capsule: 40 pt across its short side.
    public static let cornerRadius = horizontalHeight / 2
    /// A compact pill (state dot and level only) at a side edge.
    static let verticalSize = (width: 40.0, height: 112.0)
    /// The round pill under the pointer during a drag.
    static let dragDiameter = 40.0
    static let bottomInset = 24.0
    static let sideInset = 12.0
    /// A press that moves less than this is a click, not a drag.
    static let dragThreshold = 4.0

    /// `isCompact`: the pill shows only the state dot and the level, so at a side edge it can stand
    /// vertical. A pill with text stays horizontal at every anchor.
    public static func isVertical(at anchor: IndicatorAnchor, isCompact: Bool) -> Bool {
        isCompact && anchor != .bottomCenter
    }

    /// `contentWidth`: what the horizontal pill's content needs; a vertical pill ignores it.
    public static func frame(
        at anchor: IndicatorAnchor, isCompact: Bool, contentWidth: Double, in visibleFrame: ScreenRect
    ) -> ScreenRect {
        let size =
            isVertical(at: anchor, isCompact: isCompact)
            ? verticalSize : (width: min(max(contentWidth, minWidth), maxWidth), height: horizontalHeight)
        let x =
            switch anchor {
            case .bottomCenter: visibleFrame.mid.x - size.width / 2
            case .left: visibleFrame.minX + sideInset
            case .right: visibleFrame.maxX - sideInset - size.width
            }
        let y =
            anchor == .bottomCenter
            ? visibleFrame.minY + bottomInset
            : visibleFrame.mid.y - size.height / 2
        return ScreenRect(x: x, y: y, width: size.width, height: size.height)
    }

    /// The small round idle pill ("Show indicator: Always") at its anchor: where the pill with text centers at
    /// the bottom, and mid-height at a side edge.
    public static func roundFrame(at anchor: IndicatorAnchor, in visibleFrame: ScreenRect) -> ScreenRect {
        let x =
            switch anchor {
            case .bottomCenter: visibleFrame.mid.x - dragDiameter / 2
            case .left: visibleFrame.minX + sideInset
            case .right: visibleFrame.maxX - sideInset - dragDiameter
            }
        let y = anchor == .bottomCenter ? visibleFrame.minY + bottomInset : visibleFrame.mid.y - dragDiameter / 2
        return ScreenRect(x: x, y: y, width: dragDiameter, height: dragDiameter)
    }

    public static func dragFrame(centeredAt point: ScreenPoint) -> ScreenRect {
        let radius = dragDiameter / 2
        return ScreenRect(x: point.x - radius, y: point.y - radius, width: dragDiameter, height: dragDiameter)
    }

    /// The anchor whose drop target center is nearest `point`.
    public static func nearestAnchor(to point: ScreenPoint, in visibleFrame: ScreenRect) -> IndicatorAnchor {
        func distance(to anchor: IndicatorAnchor) -> Double {
            let center = frame(at: anchor, isCompact: true, contentWidth: minWidth, in: visibleFrame).mid
            return center.distance(to: point)
        }
        return IndicatorAnchor.allCases.min { distance(to: $0) < distance(to: $1) } ?? .bottomCenter
    }

    /// What a click on the pill (not its button) does, as a chord tap: it stops a recording, and with "Show indicator:
    /// Always" it starts one from the idle pill, unless a development build gives way to the release app
    /// (`InstallYield`). Nil elsewhere: the click does nothing. VoiceOver names the pill's press after it.
    public static func click(in state: DictationState, showsIdlePill: Bool, isYielding: Bool) -> PillClick? {
        guard state.notice == nil else { return nil }
        return switch state.phase {
        case .recording: .stopsDictation
        case .idle: showsIdlePill && !isYielding ? .startsDictation : nil
        case .transcribing, .cleaning, .undoable, .polishing: nil
        }
    }

    public static func isDrag(from start: ScreenPoint, to point: ScreenPoint) -> Bool {
        start.distance(to: point) >= dragThreshold
    }

    /// The index of the screen that holds most of `window`, or nil when no screen holds any of it.
    public static func screenIndex(holding window: ScreenRect, among screens: [ScreenRect]) -> Int? {
        let areas = screens.map { $0.overlapArea(with: window) }
        guard let best = areas.indices.max(by: { areas[$0] < areas[$1] }), areas[best] > 0 else { return nil }
        return best
    }

    /// Flips a window server rect (origin top left of the primary screen) to AppKit screen coordinates.
    public static func screenRect(fromWindowServer rect: ScreenRect, primaryScreenHeight: Double) -> ScreenRect {
        ScreenRect(x: rect.x, y: primaryScreenHeight - rect.y - rect.height, width: rect.width, height: rect.height)
    }
}
