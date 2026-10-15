import KotobaCore

// The indicator's two settings in General: when the pill shows and where it sits.

/// When the pill shows ("Show indicator").
enum IndicatorVisibility: String, CaseIterable {
    /// The pill shows only while a dictation or its message is live. The default.
    case whileDictating
    /// A small round pill stays at idle; a click on it starts and stops a dictation.
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
