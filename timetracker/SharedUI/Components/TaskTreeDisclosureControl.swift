import SwiftUI

/// The expand/collapse chevron of one task-tree row, or the empty slot that
/// keeps nested leaf rows aligned with their expandable siblings.
struct TaskTreeDisclosureControl: View {
    let slot: TaskTreeDisclosureSlot
    let isExpanded: Bool
    let targetSize: CGFloat
    let accessibilityIdentifier: String
    let taskTitle: String
    let toggle: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        switch slot {
        case .control:
            Button(action: toggle) {
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .rotationEffect(.degrees(isExpanded ? 90 : 0))
                    .animation(reduceMotion ? nil : AppMotion.stateChange, value: isExpanded)
                    .foregroundStyle(.secondary)
                    .frame(width: targetSize, height: targetSize)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier(accessibilityIdentifier)
            .accessibilityLabel(AppStrings.localized(isExpanded ? "tasks.collapse" : "tasks.expand"))
            .accessibilityValue(taskTitle)
        case .reserved:
            Color.clear
                .frame(width: targetSize, height: targetSize)
                .accessibilityHidden(true)
        case .none:
            EmptyView()
        }
    }
}
