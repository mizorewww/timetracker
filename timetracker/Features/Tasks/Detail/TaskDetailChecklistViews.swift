import SwiftUI

struct TaskDetailChecklistSection: View {
    let store: TimeTrackerStore
    let task: TaskNode

    private var checklistItems: [ChecklistItem] {
        store.checklistItems(for: task.id)
    }

    @ViewBuilder
    var body: some View {
        if !checklistItems.isEmpty {
            Section {
                ForEach(checklistItems, id: \.id) { item in
                    ChecklistDisplayRow(
                        title: item.title,
                        isCompleted: item.isCompleted,
                        iconName: store.checklistIconName(for: item),
                        colorHex: store.checklistColorHex(for: item)
                    ) {
                        store.toggleChecklistItem(item)
                    }
                }
            } header: {
                TaskDetailChecklistHeader(
                    title: AppStrings.localized("editor.checklist.title"),
                    progress: store.checklistProgress(for: task.id).label
                )
            }
        }
    }
}

private struct TaskDetailChecklistHeader: View {
    let title: String
    let progress: String
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        if dynamicTypeSize.isAccessibilitySize {
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                Text(progress)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            HStack {
                Text(title)
                Spacer()
                Text(progress)
                    .foregroundStyle(.secondary)
            }
        }
    }
}
