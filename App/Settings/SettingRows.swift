import SwiftUI

/// A switch with a title and one grey subtitle, in a page's row layout (`PageRow`). The mini switch is what a grouped
/// form row draws.
struct SwitchRow: View {
    let title: String
    let subtitle: String?
    @Binding var isOn: Bool

    init(_ title: String, subtitle: String?, isOn: Binding<Bool>) {
        self.title = title
        self.subtitle = subtitle
        _isOn = isOn
    }

    var body: some View {
        PageRow(title: title, subtitle: subtitle) {
            Toggle(title, isOn: $isOn)
                .labelsHidden()
                .toggleStyle(.switch)
                .controlSize(.mini)
        }
    }
}

/// One choice of a few, as a row: its name, what it is in plain words, and a check on the chosen one (the speech and
/// cleanup models). Custom: a picker draws no line under its choices, and the plan keeps each model's name with a
/// plain description (docs/research/ui-redesign.md, Copy).
struct ChoiceRow: View {
    let title: String
    let subtitle: String
    let isChosen: Bool
    let choose: () -> Void

    var body: some View {
        Button(action: choose) {
            PageRow(title: title, subtitle: subtitle) {
                Image(systemName: "checkmark")
                    .fontWeight(.semibold)
                    .foregroundStyle(.tint)
                    .opacity(isChosen ? 1 : 0)
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isChosen ? .isSelected : [])
    }
}
