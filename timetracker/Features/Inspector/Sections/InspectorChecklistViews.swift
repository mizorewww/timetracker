import SwiftUI

struct TaskChecklistPanel: View {
    @ObservedObject var store: TimeTrackerStore
    let task: TaskNode
    @State private var newChecklistTitle = ""
    @State private var showsAllItems = false

    private var items: [ChecklistItem] {
        store.checklistItems(for: task.id)
    }

    private var visibleItems: [ChecklistItem] {
        items.sorted { lhs, rhs in
            if lhs.isCompleted != rhs.isCompleted {
                return !lhs.isCompleted
            }
            if lhs.sortOrder == rhs.sortOrder {
                return lhs.createdAt < rhs.createdAt
            }
            return lhs.sortOrder < rhs.sortOrder
        }
    }

    private var displayedItems: [ChecklistItem] {
        if showsAllItems {
            return visibleItems
        }
        return Array(visibleItems.prefix(5))
    }

    private var progress: ChecklistProgress {
        store.checklistProgress(for: task.id)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(.app("checklist.title"))
                    .font(.headline)
                Spacer()
                if progress.totalCount > 0 {
                    Text(progress.label)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
            }

            VStack(alignment: .leading, spacing: 10) {
                if progress.totalCount > 0 {
                    ProgressView(value: progress.fraction)
                }
                if displayedItems.isEmpty {
                    Text(.app("checklist.noItems"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(displayedItems, id: \.id) { item in
                            ChecklistDisplayRow(
                                title: item.title,
                                isCompleted: item.isCompleted
                            ) {
                                withAnimation(.snappy(duration: 0.22)) {
                                    store.toggleChecklistItem(item)
                                }
                            }
                        }
                    }
                }
                InlineChecklistAddRow(title: $newChecklistTitle) {
                    store.addChecklistItem(taskID: task.id, title: newChecklistTitle)
                    newChecklistTitle = ""
                }
                if items.count > 5 {
                    Button {
                        showsAllItems.toggle()
                    } label: {
                        Label(
                            showsAllItems ? AppStrings.localized("checklist.showLess") : String(format: AppStrings.localized("checklist.moreFormat"), items.count - 5),
                            systemImage: showsAllItems ? "chevron.up.circle" : "chevron.down.circle"
                        )
                    }
                    .buttonStyle(.plain)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
                Text(.app("checklist.keepCompletedHint"))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .appCard(padding: 14)
        }
    }
}
