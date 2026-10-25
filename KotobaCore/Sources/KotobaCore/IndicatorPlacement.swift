/// Where the recording indicator sits on its screen.
public enum IndicatorAnchor: String, CaseIterable, Sendable {
    /// A horizontal pill just above the Dock or the screen bottom. The default.
    case bottomCenter
    /// Mid-height on the left edge; vertical when the pill shows no words.
    case left
    /// Mid-height on the right edge; vertical when the pill shows no words.
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
    public var mid: ScreenPoint { ScreenPoint(x: x + width / 2, y: y + height / 2) }

    func overlapArea(with other: Self) -> Double {
        let width = min(maxX, other.maxX) - max(minX, other.minX)
        let height = min(maxY, other.maxY) - max(minY, other.minY)
        return width > 0 && height > 0 ? width * height : 0
    }
}

/// The indicator's placement math: the room the pill's window covers at each anchor, inside the screen's visible frame
/// (so the pill never sits under the Dock, menu bar or notch), where the capsule sits in that room, and the anchor
/// nearest a drop point. The capsule's thickness is the pill buttons' measured height plus their margin; the App
/// measures it and passes it in.
public enum IndicatorPlacement {
    /// The longest pill: about 34 characters of text beside a button (CODING_STANDARDS.md, "User-facing text" 7).
    public static let maxWidth = 360.0
    /// The idle bar ("Show indicator: Always"): its long and short side, turned 90° at a side edge (Wispr Flow's and
    /// Jot's rest size).
    public static let idleBarLength = 40.0
    public static let idleBarThickness = 8.0
    static let bottomInset = 24.0
    static let sideInset = 12.0
    /// A press that moves less than this is a click, not a drag.
    static let dragThreshold = 4.0

    /// A pill with no words (bars, the sweep, the check, the idle bar) stands vertical at a side edge. Words, keys or the
    /// time keep it horizontal at every anchor, so they read left to right.
    public static func isVertical(at anchor: IndicatorAnchor, hasWords: Bool) -> Bool {
        !hasWords && anchor != .bottomCenter
    }

    /// The room the pill's window covers at `anchor`: every capsule the pill takes there fits, so the capsule changes
    /// shape inside it and the window does not move. A row along the bottom; a square at a side edge, where the pill
    /// stands vertical or reaches inward.
    public static func room(at anchor: IndicatorAnchor, thickness: Double, in visibleFrame: ScreenRect) -> ScreenRect {
        let y = visibleFrame.mid.y - maxWidth / 2
        return switch anchor {
        case .bottomCenter:
            ScreenRect(
                x: visibleFrame.mid.x - maxWidth / 2, y: visibleFrame.minY + bottomInset, width: maxWidth,
                height: thickness)
        case .left: ScreenRect(x: visibleFrame.minX + sideInset, y: y, width: maxWidth, height: maxWidth)
        case .right: ScreenRect(x: visibleFrame.maxX - sideInset - maxWidth, y: y, width: maxWidth, height: maxWidth)
        }
    }

    /// Where a capsule of `width` by `height` sits in `room`. Every shape shares one centre line: the bottom room's
    /// middle, or at a side edge the axis of a capsule `thickness` across that touches the edge. A capsule at least
    /// that wide starts at the edge and reaches inward; a thinner one (the idle bar) centres on the axis.
    public static func capsule(
        width: Double, height: Double, at anchor: IndicatorAnchor, thickness: Double, in room: ScreenRect
    ) -> ScreenRect {
        let y = room.mid.y - height / 2
        let x =
            switch anchor {
            case .bottomCenter: room.mid.x - width / 2
            case .left: width >= thickness ? room.minX : room.minX + (thickness - width) / 2
            case .right: width >= thickness ? room.maxX - width : room.maxX - (thickness + width) / 2
            }
        return ScreenRect(x: x, y: y, width: width, height: height)
    }

    /// The pill's room while the owner drags it: the room it had, moved as far as the pointer moved since the press. The
    /// pill keeps its look and its place under the pointer; nothing else shows.
    public static func draggedRoom(_ room: ScreenRect, from press: ScreenPoint, to point: ScreenPoint) -> ScreenRect {
        ScreenRect(x: room.x + point.x - press.x, y: room.y + point.y - press.y, width: room.width, height: room.height)
    }

    /// The anchor nearest `point` (the dropped capsule's centre): the anchor whose pill centre line, a capsule
    /// `thickness` across in its room, is nearest.
    public static func nearestAnchor(to point: ScreenPoint, thickness: Double, in visibleFrame: ScreenRect)
        -> IndicatorAnchor
    {
        func distance(to anchor: IndicatorAnchor) -> Double {
            let room = room(at: anchor, thickness: thickness, in: visibleFrame)
            return capsule(width: thickness, height: thickness, at: anchor, thickness: thickness, in: room).mid
                .distance(to: point)
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
