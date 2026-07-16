import SwiftUI

struct TaskStartPickerEmptyState: View {
    let isTaskLibraryEmpty: Bool
    let onClearSearch: () -> Void
    let onCreateTask: () -> Void

    var body: some View {
        ContentUnavailableView {
            Label(
                isTaskLibraryEmpty
                    ? AppStrings.localized("tasks.empty.title")
                    : AppStrings.localized("tasks.empty.search"),
                systemImage: isTaskLibraryEmpty ? "checklist" : "magnifyingglass"
            )
        } description: {
            Text(
                isTaskLibraryEmpty
                    ? AppStrings.localized("tasks.empty.description")
                    : AppStrings.localized("timer.search.empty.description")
            )
        } actions: {
            if isTaskLibraryEmpty {
                createTaskButton
                    .buttonStyle(.borderedProminent)
            } else {
                Button(action: onClearSearch) {
                    Label(AppStrings.localized("tasks.search.clear"), systemImage: "xmark.circle")
                }
                .buttonStyle(.borderedProminent)

                createTaskButton
                    .buttonStyle(.bordered)
            }
        }
    }

    private var createTaskButton: some View {
        Button(action: onCreateTask) {
            Label(AppStrings.newTask, systemImage: "plus")
        }
    }
}
