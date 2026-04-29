import SwiftUI

struct TaskChecklistPanel: View {
    @ObservedObject var store: TimeTrackerStore
    let task: TaskNode
    @State private var newChecklistTitle = ""

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
                ForEach(visibleItems.prefix(5), id: \.id) { item in
                    ChecklistDisplayRow(item: item) {
                        withAnimation(.snappy(duration: 0.22)) {
                            store.toggleChecklistItem(item)
                        }
                    }
                }
                InlineChecklistAddRow(title: $newChecklistTitle) {
                    store.addChecklistItem(taskID: task.id, title: newChecklistTitle)
                    newChecklistTitle = ""
                }
                if items.count > 5 {
                    Text(String(format: AppStrings.localized("checklist.moreFormat"), items.count - 5))
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

private struct ChecklistDisplayRow: View {
    let item: ChecklistItem
    let toggle: () -> Void

    var body: some View {
        Button(action: toggle) {
            HStack(spacing: 10) {
                ChecklistCompletionMark(isCompleted: item.isCompleted)

                Text(item.title)
                    .lineLimit(1)
                    .strikethrough(item.isCompleted)
                    .foregroundStyle(item.isCompleted ? .secondary : .primary)
                Spacer(minLength: 0)
            }
            .font(.subheadline)
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

private struct InlineChecklistAddRow: View {
    @Binding var title: String
    let submit: () -> Void
    @FocusState private var isFocused: Bool

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "plus.circle")
                .font(.title3)
                .foregroundStyle(.blue)
                .frame(width: 30, height: 30)
            TextField(AppStrings.localized("editor.checklist.itemPlaceholder"), text: $title)
                .textFieldStyle(.plain)
                .focused($isFocused)
                .onSubmit(submitIfNeeded)
                .submitLabel(.done)
        }
        .frame(minHeight: 44)
        .contentShape(Rectangle())
        .onTapGesture {
            isFocused = true
        }
    }

    private func submitIfNeeded() {
        guard !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        submit()
        isFocused = true
    }
}
