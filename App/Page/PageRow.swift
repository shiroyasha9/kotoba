import SwiftUI

/// A row with a title, at most one grey subtitle, an optional icon and trailing content (a value, keycaps, a button):
/// the one way to write a titled row on a page. As in System Settings, the trailing content is centred on the row while
/// the subtitle fits on one line (Notifications' app rows) and sits on the title line once the text wraps (Keyboard's
/// "Keyboard navigation"). `ViewThatFits` tries the one-line layout first, so the rule needs no measured offset.
/// VoiceOver reads the title, subtitle and icon as one element and the trailing content as its own elements, as System
/// Settings' rows read "title, subtitle", then the control: a row's buttons stay buttons.
struct PageRow<Icon: View, Trailing: View>: View {
    let title: String
    var subtitle: String?
    @ViewBuilder let icon: Icon
    @ViewBuilder let trailing: Trailing

    var body: some View {
        ViewThatFits(in: .horizontal) {
            line(isOneLine: true)
            line(isOneLine: false)
        }
    }

    private func line(isOneLine: Bool) -> some View {
        HStack(alignment: isOneLine ? .center : .titleLine) {
            if Icon.self == EmptyView.self {
                RowText(title: title, subtitle: subtitle, isOneLine: isOneLine)
                    .accessibilityElement(children: .combine)
            } else {
                TileLabel(title: title, subtitle: subtitle, isOneLine: isOneLine) { icon }
            }
            Spacer()
            trailing
                .alignmentGuide(.titleLine) { $0[VerticalAlignment.center] }
        }
    }
}

extension PageRow where Icon == EmptyView {
    init(title: String, subtitle: String?, @ViewBuilder trailing: () -> Trailing) {
        self.init(title: title, subtitle: subtitle, icon: { EmptyView() }, trailing: trailing)
    }
}

/// A row's title, its one grey subtitle and its icon in the page's icon column, centred on both lines as in System
/// Settings' rows. Custom: SwiftUI's `Label` centres its icon on the first line only, so a two-line row's tile sat high
/// (owner trial, 2026-10-24), and a custom `LabelStyle` loses the form's subtitle style.
struct TileLabel<Icon: View, Extra: View>: View {
    let title: String
    var subtitle: String?
    /// Title and subtitle each kept on one line (`PageRow` tries this first).
    var isOneLine = false
    @ViewBuilder let icon: Icon
    /// Under the subtitle: a header card's link.
    @ViewBuilder var extra: Extra

    var body: some View {
        RowLeading {
            icon
        } content: {
            RowText(title: title, subtitle: subtitle, isOneLine: isOneLine, extra: { extra })
        }
        .accessibilityElement(children: .combine)
    }
}

extension TileLabel where Extra == EmptyView {
    init(title: String, subtitle: String?, isOneLine: Bool = false, @ViewBuilder icon: () -> Icon) {
        self.init(title: title, subtitle: subtitle, isOneLine: isOneLine, icon: icon) { EmptyView() }
    }
}

/// A row's title and its one grey subtitle in the form's own styles (body; subheadline, secondary), measured equal in
/// the snapshot. The title marks `VerticalAlignment.titleLine`.
struct RowText<Extra: View>: View {
    let title: String
    var subtitle: String?
    var isOneLine = false
    @ViewBuilder var extra: Extra

    var body: some View {
        VStack(alignment: .leading) {
            Text(title)
                .fixedSize(horizontal: isOneLine, vertical: false)
                .alignmentGuide(.titleLine) { $0[VerticalAlignment.center] }
            if let subtitle {
                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: isOneLine, vertical: false)
            }
            extra
        }
    }
}

extension RowText where Extra == EmptyView {
    init(title: String, subtitle: String?, isOneLine: Bool = false) {
        self.init(title: title, subtitle: subtitle, isOneLine: isOneLine) { EmptyView() }
    }
}

extension VerticalAlignment {
    private enum TitleLine: AlignmentID {
        static func defaultValue(in dimensions: ViewDimensions) -> CGFloat { dimensions[VerticalAlignment.center] }
    }

    /// The middle of a row's title line (`RowText`).
    static let titleLine = VerticalAlignment(TitleLine.self)
}

/// A page's icon column: the icon in a column `PageMetrics.rowTileSide` wide, then the text after
/// `PageMetrics.tileTextGap`, so the text of every row with an icon starts at one x (owner trial, 2026-10-25: Home's
/// card and rows started their text 8 pt apart). A row whose text is not a title and a subtitle (a dictation's line)
/// puts its icon and text here.
struct RowLeading<Icon: View, Content: View>: View {
    @ViewBuilder let icon: Icon
    @ViewBuilder let content: Content

    var body: some View {
        HStack(spacing: PageMetrics.tileTextGap) {
            icon
                .frame(width: PageMetrics.rowTileSide)
            content
        }
    }
}

extension View {
    /// Starts this view in the page's text column, under the title of the row above (a dictation's full text, its
    /// buttons), as System Settings starts every paragraph of a row with an icon (review-window.md T4).
    func inRowTextColumn() -> some View {
        padding(.leading, PageMetrics.rowTileSide + PageMetrics.tileTextGap)
    }
}

/// A switch with a title and at most one grey subtitle: a `PageRow` with the switch as its trailing content, so it
/// aligns as every row does (centred while the subtitle fits on one line, on the title line once it wraps). The switch
/// keeps the title as its VoiceOver label.
struct PageToggle: View {
    let title: String
    var subtitle: String?
    @Binding var isOn: Bool

    var body: some View {
        PageRow(title: title, subtitle: subtitle) {
            Toggle(title, isOn: $isOn)
                .labelsHidden()
                .toggleStyle(.switch)
        }
    }
}
