import AppKit
import KotobaCore

extension DropGuides {
    /// Each guide as it shows during a drag, plain and tinted as the nearest: the idle bar's capsule at its anchor. The
    /// run fails on a guide that is a circle or not a capsule (owner QA 4, U3: the guides match the pill's shape).
    static func snapshots() -> [Snapshot] {
        IndicatorAnchor.allCases.flatMap { anchor in
            [false, true].map { isNearest in
                var snapshot = Snapshot(name: "pill-guide-\(anchor.rawValue)\(isNearest ? "-nearest" : "")") {
                    let frame = IndicatorPlacement.guide(
                        at: anchor, thickness: Double(PillGeometry.height), in: sampleVisibleFrame)
                    let glass = glass(size: NSSize(width: frame.width, height: frame.height))
                    tint(glass, isNearest: isNearest)
                    glass.alphaValue = alpha(isNearest: isNearest)
                    return glass
                } check: { view in
                    guard let glass = view as? NSGlassEffectView else { return "the guide is not glass" }
                    let size = glass.frame.size
                    if size.width == size.height { return "the guide at \(anchor.rawValue) is a circle" }
                    return glass.cornerRadius == min(size.width, size.height) / 2
                        ? nil : "the guide at \(anchor.rawValue) is not a capsule (radius \(glass.cornerRadius))"
                }
                // The guides float over other apps, as the pill does.
                snapshot.floatsOverDesktop = true
                return snapshot
            }
        }
    }

    /// A 14-inch MacBook Pro's visible frame; the guide's shape does not depend on it.
    private static let sampleVisibleFrame = ScreenRect(x: 0, y: 70, width: 1512, height: 845)
}
