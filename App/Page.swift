import AppKit
import SwiftUI

// The main window's visual system for 0.5.0 (docs/research/ui-redesign.md, "Window"). A page is a grouped form in a
// centred column, opened by a header card. Cards are the form's sections and rows are its rows, so heights, paddings,
// corner radii and text colours are the system's. Symbols take the font of the text next to them. The few sizes Apple
// gives no value for live in `PageMetrics.swift`, each with its source.

/// A page of the main window: a grouped form whose sections stay in a centred column at most `PageMetrics.columnWidth`
/// wide. The margins are the scroll view's content margins, so the scroll bar stays at the window's edge and the whole
/// width scrolls.
struct PageForm<Content: View>: View {
    @ViewBuilder let content: Content
    @State private var width: CGFloat = 0

    var body: some View {
        Form {
            content
        }
        .formStyle(.grouped)
        .contentMargins(.horizontal, sideMargin, for: .scrollContent)
        .onGeometryChange(for: CGFloat.self, of: \.size.width) { width = $0 }
    }

    /// Nil keeps the form's own margin until the window is wider than the column.
    private var sideMargin: CGFloat? {
        width > PageMetrics.columnWidth ? (width - PageMetrics.columnWidth) / 2 : nil
    }
}

/// The card that opens a page, as in System Settings' Screen Time: an icon, the page's name, one line on what the page
/// does, and a link when there is more to learn. Put it in the page's first `Section`.
struct PageHeader<Icon: View>: View {
    let title: String
    let summary: String
    var link: (title: String, action: () -> Void)?
    @ViewBuilder let icon: Icon

    var body: some View {
        Label {
            Text(title)
            Text(summary)
            if let link {
                Button(link.title, action: link.action)
                    .buttonStyle(.link)
            }
        } icon: {
            icon
        }
    }
}

/// A symbol in white on a rounded square of a colour, as in the System Settings sidebar and Screen Time's rows. The
/// symbol keeps its weight and optical size: it is drawn at a point size, never stretched. Custom: SwiftUI has no
/// settings icon style.
struct SymbolTile: View {
    let systemImage: String
    let tint: Color
    let side: CGFloat

    var body: some View {
        Image(systemName: systemImage)
            .symbolVariant(.fill)
            .font(.system(size: side * PageMetrics.tileSymbolRatio, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: side, height: side)
            .background(tint.gradient, in: .rect(cornerRadius: side * PageMetrics.tileCornerRatio, style: .continuous))
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
    let side: CGFloat

    var body: some View {
        Group {
            if let icon {
                // An app icon is a bitmap: it scales; a symbol never does.
                Image(nsImage: icon).resizable().interpolation(.high)
            } else {
                Image(systemName: "app.dashed").font(.system(size: side * PageMetrics.tileSymbolRatio))
            }
        }
        .frame(width: side, height: side)
        .accessibilityHidden(true)
    }
}

/// A chord drawn as keys, one keycap per key. Custom: macOS has no keycap view.
struct Keycaps: View {
    let keys: [String]

    var body: some View {
        HStack {
            ForEach(Array(keys.enumerated()), id: \.offset) { _, key in
                Text(key)
                    .font(.title2.weight(.medium))
                    .padding(.horizontal, PageMetrics.keycapInset)
                    .frame(minWidth: PageMetrics.keycapSide, minHeight: PageMetrics.keycapSide)
                    .fixedSize()
                    .background(.fill.tertiary, in: Self.shape)
                    .overlay(Self.shape.strokeBorder(.separator))
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(keys.joined(separator: " "))
    }

    private static let shape = RoundedRectangle(
        cornerRadius: PageMetrics.keycapSide * PageMetrics.tileCornerRatio, style: .continuous)
}
