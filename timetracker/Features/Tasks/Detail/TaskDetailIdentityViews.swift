import SwiftUI

struct TaskDetailIdentityRow: View {
    let store: TimeTrackerStore
    let task: TaskNode
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            TaskIcon(task: task, size: 44)
            identityText
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
    }

    private var identityText: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(store.parentPath(for: task) ?? AppStrings.localized("task.root"))
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 2)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
