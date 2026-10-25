import Foundation
import KotobaCore
import Observation

// The indicator's two settings in General: when the pill shows and where it sits.

/// When the pill shows ("Show indicator").
enum IndicatorVisibility: String, CaseIterable {
    /// The pill shows only while a dictation or its message is live. The default.
    case whileDictating
    /// An idle bar stays at idle; hovering it shows the hands-free chord, and a click on it starts a dictation.
    case always

    /// The menu title.
    var title: String {
        switch self {
        case .whileDictating: "While Dictating"
        case .always: "Always"
        }
    }
}

extension IndicatorAnchor {
    /// The menu title.
    var title: String {
        switch self {
        case .bottomCenter: "Bottom Center"
        case .left: "Left"
        case .right: "Right"
        }
    }
}

/// Where the pill sits: one observed value that the pill's drop and General's Position picker both read and write, so
/// the picker follows a drop at once (audit-1 A1). The app's position is saved in UserDefaults.
@MainActor
@Observable
final class IndicatorPosition {
    private static let key = AppDefaults.Key.indicatorAnchor.rawValue

    var anchor: IndicatorAnchor {
        didSet {
            if isSaved {
                UserDefaults.standard.set(anchor.rawValue, forKey: Self.key)
            }
        }
    }

    @ObservationIgnored private let isSaved: Bool

    /// The saved position.
    init() {
        anchor = UserDefaults.standard.string(forKey: Self.key).flatMap(IndicatorAnchor.init) ?? .bottomCenter
        isSaved = true
    }

    /// A stand-in for snapshots: starts at `anchor` and saves nothing.
    init(sample anchor: IndicatorAnchor) {
        self.anchor = anchor
        isSaved = false
    }
}
