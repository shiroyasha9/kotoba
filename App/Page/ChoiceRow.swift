import SwiftUI

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
