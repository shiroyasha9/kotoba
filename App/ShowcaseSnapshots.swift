import AppKit

/// The README's and the site's images (`make readme-images`, `--showcase <folder>`): the main window as macOS draws it
/// (title bar, glass toolbar, rounded corners) and the pill's main looks, on a colourful stage, light and dark, at 2x.
/// The window is the real one, captured and put on the stage with an active window's shadow (`drawWindow`). The pill's
/// glass refracts the stage drawn in its own window. macOS 27 draws the sidebar edge to edge, over the page's background: no Apple app has
/// a floating sidebar there (sidebar spike, 2026-10-24), so the images show it as it is.
@MainActor
enum Showcase {
    static func snapshots() -> [Snapshot] {
        Pane.showcaseSnapshots() + IndicatorPanel.showcaseSnapshots()
    }

    /// The stage around the window, on each side.
    private static let windowMargin: CGFloat = 64

    /// The window in the middle of a stage `windowMargin` larger on each side, with its shadow (`drawWindow`).
    static func windowOnStage(_ window: NSWindow, scale: CGFloat, appearance: NSAppearance) throws -> CGImage {
        let capture = try SnapshotCapture.image(of: window, scale: scale)
        let margin = Int((windowMargin * scale).rounded())
        let width = capture.width + 2 * margin
        let height = capture.height + 2 * margin
        guard let space = CGColorSpace(name: CGColorSpace.sRGB),
            let context = CGContext(
                data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0, space: space,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { throw ShowcaseError.noBitmap }
        Stage.draw(in: context, size: CGSize(width: width, height: height), isDark: isDark(appearance))
        drawWindow(
            capture,
            in: CGRect(x: margin, y: margin, width: capture.width, height: capture.height), of: context, scale: scale,
            isDark: isDark(appearance))
        guard let image = context.makeImage() else { throw ShowcaseError.noBitmap }
        return image
    }

    /// Draws `capture`, a window as `SnapshotCapture` has it, in `rect` of `context`, with the shadow macOS gives an
    /// active window. The window server leaves the shadow out of a window that was never on screen (2026-10-25: the
    /// pixels around the window matched the stage), so it is drawn here from the window's own shape (its alpha): wide
    /// and soft under it, and close at its edge. `scale` is pixels per point.
    static func drawWindow(_ capture: CGImage, in rect: CGRect, of context: CGContext, scale: CGFloat, isDark: Bool) {
        for (drop, blur, alpha) in [(18.0, 50.0, isDark ? 0.55 : 0.24), (0.0, 2.0, isDark ? 0.7 : 0.2)] {
            context.saveGState()
            context.setShadow(
                offset: CGSize(width: 0, height: -drop * scale), blur: blur * scale,
                color: CGColor(gray: 0, alpha: alpha))
            context.draw(capture, in: rect)
            context.restoreGState()
        }
    }

    private enum ShowcaseError: Error {
        case noBitmap
    }
}

private func isDark(_ appearance: NSAppearance) -> Bool {
    appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
}

/// The showcase's backdrop: soft colour fields on a pale (light) or deep (dark) ground, like a product shot. Fixed sRGB
/// values in proportion to the size, so every image of one appearance has the same light, never the owner's wallpaper.
enum Stage {
    /// A colour field: its centre and radius in fractions of the stage (the radius of its longer side), its colour
    /// (red, green, blue, alpha at the centre).
    private struct Field {
        let x: CGFloat
        let y: CGFloat
        let radius: CGFloat
        let color: [CGFloat]
    }

    /// Coral (the icon's), rose, violet and sky, one at each corner, so they show in the margin around a window.
    private static let lightFields = [
        Field(x: 0.0, y: 0.05, radius: 0.75, color: [1.0, 0.56, 0.45, 0.6]),
        Field(x: 0.3, y: 1.0, radius: 0.55, color: [0.98, 0.5, 0.75, 0.45]),
        Field(x: 1.0, y: 0.95, radius: 0.7, color: [0.6, 0.48, 0.98, 0.5]),
        Field(x: 0.95, y: 0.0, radius: 0.6, color: [0.35, 0.75, 0.98, 0.45]),
    ]

    private static let darkFields = [
        Field(x: 0.0, y: 0.05, radius: 0.75, color: [0.91, 0.33, 0.24, 0.55]),
        Field(x: 0.3, y: 1.0, radius: 0.55, color: [0.75, 0.15, 0.55, 0.45]),
        Field(x: 1.0, y: 0.95, radius: 0.7, color: [0.42, 0.25, 0.85, 0.55]),
        Field(x: 0.95, y: 0.0, radius: 0.6, color: [0.15, 0.4, 0.9, 0.5]),
    ]

    static func draw(in context: CGContext, size: CGSize, isDark: Bool) {
        guard let space = CGColorSpace(name: CGColorSpace.sRGB) else { return }
        let ground: [CGFloat] =
            isDark ? [0.07, 0.06, 0.12, 1, 0.04, 0.04, 0.08, 1] : [0.99, 0.97, 0.96, 1, 0.96, 0.95, 0.99, 1]
        if let gradient = CGGradient(colorSpace: space, colorComponents: ground, locations: [0, 1], count: 2) {
            context.drawLinearGradient(
                gradient, start: CGPoint(x: 0, y: size.height), end: .zero, options: [])
        }
        let side = max(size.width, size.height)
        for field in isDark ? darkFields : lightFields {
            let rgb = Array(field.color.prefix(3))
            let alpha = field.color[3]
            // Full at the centre, half at half the radius, none at the edge: a soft field with no rim.
            let components = rgb + [alpha] + rgb + [alpha / 2] + rgb + [0]
            guard
                let gradient = CGGradient(
                    colorSpace: space, colorComponents: components, locations: [0, 0.5, 1], count: 3)
            else { continue }
            let centre = CGPoint(x: field.x * size.width, y: field.y * size.height)
            context.drawRadialGradient(
                gradient, startCenter: centre, startRadius: 0, endCenter: centre, endRadius: field.radius * side,
                options: [])
        }
    }
}

extension Snapshots {
    /// What a view sits on in its snapshot window.
    enum Surface {
        /// The window background, as a pane in its window.
        case window
        /// A fixed grey desktop, for a view that floats over other apps (the pill).
        case desktop
        /// The showcase's colourful stage (`Showcase`).
        case stage
    }

    /// What a view sits on: the window background; for a view that floats over other apps a fixed desktop, the same
    /// in light, in dark and in every run, never the owner's wallpaper; or the showcase's stage. The desktop's grey
    /// ramp, light at the left and dark at the right, shows the view over bright and dark content in one image; its
    /// thin black and white stripes give the glass edges to bend. Neutral greys keep the glass's own tint visible.
    /// Fixed sRGB values, not theme colors, so the desktop does not change with the appearance.
    final class Backdrop: NSView {
        private let surface: Surface

        init(frame: NSRect, surface: Surface) {
            self.surface = surface
            super.init(frame: frame)
        }

        @available(*, unavailable)
        required init?(coder: NSCoder) {
            fatalError("Backdrop is built in code")
        }

        override func draw(_ dirtyRect: NSRect) {
            switch surface {
            case .window:
                NSColor.windowBackgroundColor.setFill()
                dirtyRect.fill()
            case .stage:
                guard let context = NSGraphicsContext.current?.cgContext else { return }
                Stage.draw(in: context, size: bounds.size, isDark: isDark(effectiveAppearance))
            case .desktop:
                let light = NSColor(srgbRed: 0.93, green: 0.93, blue: 0.92, alpha: 1)
                let dark = NSColor(srgbRed: 0.16, green: 0.17, blue: 0.2, alpha: 1)
                NSGradient(starting: light, ending: dark)?.draw(in: bounds, angle: 0)
                for (offset, white) in [(0.0, 0.0), (8.0, 1.0)] {
                    NSColor(srgbRed: white, green: white, blue: white, alpha: 0.3).setFill()
                    for x in stride(from: offset, to: bounds.width, by: 16) {
                        NSRect(x: x, y: 0, width: 2, height: bounds.height).fill(using: .sourceOver)
                    }
                }
            }
        }
    }
}

/// The pills on the stage: one above the other in the middle of a stage one pill wide (the longest), each look's
/// image the same width, so the README and the site can line them up.
extension Showcase {
    private static let pillStageWidth: CGFloat = 400
    private static let pillGap: CGFloat = 16
    private static let pillMargin: CGFloat = 24

    /// The pills in a view that `Snapshots` puts on the stage (its 16 pt padding makes the stage 400 pt wide).
    static func pillStage(_ pills: [NSView]) -> NSView {
        let height =
            pills.map(\.frame.height).reduce(0, +) + pillGap * CGFloat(pills.count - 1) + 2 * pillMargin
        let stage = NSView(frame: NSRect(x: 0, y: 0, width: pillStageWidth - 32, height: height))
        var top = height - pillMargin
        for pill in pills {
            top -= pill.frame.height
            pill.setFrameOrigin(NSPoint(x: ((stage.frame.width - pill.frame.width) / 2).rounded(), y: top))
            stage.addSubview(pill)
            top -= pillGap
        }
        return stage
    }
}
