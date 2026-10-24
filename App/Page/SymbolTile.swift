import AppKit
import SwiftUI

/// A symbol in white on a rounded square of a colour, as in the System Settings sidebar and Screen Time's rows. The
/// symbol keeps its weight and optical size: it is drawn at a point size, never stretched. Custom: SwiftUI has no
/// settings icon style.
struct SymbolTile: View {
    let tint: Color
    let side: CGFloat
    /// The symbol's filled form when it has one.
    private let name: String
    private let pointSize: CGFloat
    @Environment(\.displayScale) private var displayScale

    init(systemImage: String, tint: Color, side: CGFloat) {
        self.tint = tint
        self.side = side
        let filled = systemImage + ".fill"
        name = NSImage(systemSymbolName: filled, accessibilityDescription: nil) == nil ? systemImage : filled
        // Each symbol gets the point size at which its larger side fills `tileGlyphShare` of the tile, read from the
        // symbol's own bounds at a probe size, so a wide house and a narrow mic look the same size.
        let probe: CGFloat = 100
        let bounds = NSImage(systemSymbolName: name, accessibilityDescription: nil)?
            .withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: probe, weight: Self.weight))?.size
        let larger = bounds.map { max($0.width, $0.height) } ?? probe
        pointSize = probe * side * PageMetrics.tileGlyphShare / larger
    }

    /// Apple's tile glyphs are light and even; semibold looked heavy (review-window.md, 1).
    private static let weight = NSFont.Weight.medium

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: side * PageMetrics.tileCornerRatio, style: .continuous)
        Image(systemName: name)
            .font(.system(size: pointSize, weight: .medium))
            // White on the tile's colour in light and dark, as System Settings' tiles.
            .foregroundStyle(.white)
            .frame(width: side, height: side)
            .background(tint.gradient, in: shape)
            // The rim and soft ring of Apple's tiles (review-window.md T1), so a tile reads as an icon, not a flat
            // swatch: a lighter hairline at the edge, and the system shadow under it.
            .overlay(shape.strokeBorder(.white.opacity(PageMetrics.tileRimOpacity), lineWidth: 1 / displayScale))
            .shadow(radius: side * PageMetrics.tileShadowRadiusRatio, y: side * PageMetrics.tileShadowDropRatio)
            .accessibilityHidden(true)
    }
}

/// A sidebar tile whose side follows the owner's sidebar icon size.
struct SidebarTile: View {
    let systemImage: String
    let tint: Color
    @Environment(\.sidebarRowSize) private var rowSize

    var body: some View {
        SymbolTile(systemImage: systemImage, tint: tint, side: PageMetrics.sidebarTileSide(rowSize))
    }
}

/// An app's icon at a row's icon size; a dashed app symbol when the app is unknown.
struct AppIconView: View {
    let icon: NSImage?
    var side = PageMetrics.rowTileSide

    var body: some View {
        Group {
            if let icon {
                // An app icon is a bitmap: it scales; a symbol never does.
                Image(nsImage: icon).resizable().interpolation(.high)
            } else {
                Image(systemName: "app.dashed").font(.system(size: side * PageMetrics.tileGlyphShare))
            }
        }
        .frame(width: side, height: side)
        .accessibilityHidden(true)
    }
}
