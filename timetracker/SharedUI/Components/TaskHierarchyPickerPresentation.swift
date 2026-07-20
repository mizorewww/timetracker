import SwiftUI

extension TaskHierarchyPicker {
    func emptyState(_ projection: TaskHierarchyProjection) -> some View {
        ContentUnavailableView {
            Label(
                emptyStateTitle(projection),
                systemImage: projection.hasVisibleTasks
                    ? "magnifyingglass"
                    : "checklist"
            )
        } description: {
            Text(emptyStateDescription(projection))
        } actions: {
            if projection.isSearching {
                Button(AppStrings.localized("tasks.search.clear")) {
                    searchText = ""
                }
                .buttonStyle(.borderedProminent)
            }

            if case .timer = mode, let onCreateTask {
                createTaskButton(
                    action: onCreateTask,
                    isSecondary: projection.isSearching
                )
            }
        }
    }

    @ViewBuilder
    private func createTaskButton(
        action: @escaping () -> Void,
        isSecondary: Bool
    ) -> some View {
        if isSecondary {
            Button(action: action) {
                Label(AppStrings.newTask, systemImage: "plus")
            }
            .buttonStyle(.bordered)
        } else {
            Button(action: action) {
                Label(AppStrings.newTask, systemImage: "plus")
            }
            .buttonStyle(.borderedProminent)
        }
    }

    var navigationTitle: String {
        switch mode {
        case .timer:
            store.timerPickerMode.title
        case let .singleSelection(_, context):
            context.navigationTitle
        case let .multipleSelection(_, context, _):
            context.navigationTitle
        }
    }

    var accessibilityIdentifier: String {
        switch mode {
        case .timer:
            "timer.taskPicker"
        case let .singleSelection(_, context):
            context.accessibilityIdentifier
        case let .multipleSelection(_, context, _):
            context.accessibilityIdentifier
        }
    }

    func emptyStateTitle(
        _ projection: TaskHierarchyProjection
    ) -> String {
        if projection.hasVisibleTasks {
            return AppStrings.localized("tasks.empty.search")
        }
        switch mode {
        case .timer:
            return AppStrings.localized("tasks.empty.title")
        case let .singleSelection(_, context):
            return context.emptyStateTitle
        case let .multipleSelection(_, context, _):
            return context.emptyStateTitle
        }
    }

    func emptyStateDescription(
        _ projection: TaskHierarchyProjection
    ) -> String {
        if projection.hasVisibleTasks {
            return AppStrings.localized("tasks.search.empty.description")
        }
        switch mode {
        case .timer:
            return AppStrings.localized("tasks.empty.description")
        case let .singleSelection(_, context):
            return context.emptyStateDescription
        case let .multipleSelection(_, context, _):
            return context.emptyStateDescription
        }
    }

    var disclosureTargetSize: CGFloat {
        #if os(iOS)
        44
        #else
        24
        #endif
    }
}

extension TaskHierarchyPickerSelectionContext {
    var navigationTitle: String {
        switch self {
        case .pomodoro:
            AppStrings.localized("pomodoro.chooseTask")
        case .inboxChildTaskParent:
            AppStrings.localized("inbox.route.childTask.title")
        case .inboxChecklistTarget:
            AppStrings.localized("inbox.route.checklistItem.title")
        case .todayHeatmap:
            AppStrings.localized("heatmap.picker.title")
        }
    }
    var accessibilityIdentifier: String {
        switch self {
        case .pomodoro:
            "pomodoro.taskPicker"
        case .inboxChildTaskParent:
            "inbox.childTask.parentPicker"
        case .inboxChecklistTarget:
            "inbox.checklistItem.taskPicker"
        case .todayHeatmap:
            "settings.todayHeatmap.taskPicker"
        }
    }
    var selectionHint: String {
        switch self {
        case .pomodoro:
            AppStrings.localized("pomodoro.taskPicker.selectionHint")
        case .inboxChildTaskParent:
            AppStrings.localized("inbox.route.childTask.selectionHint")
        case .inboxChecklistTarget:
            AppStrings.localized("inbox.route.checklistItem.selectionHint")
        case .todayHeatmap:
            AppStrings.localized("heatmap.picker.selectionHint")
        }
    }
    var emptyStateTitle: String {
        switch self {
        case .pomodoro:
            AppStrings.localized("pomodoro.noTasks.title")
        case .inboxChildTaskParent, .inboxChecklistTarget, .todayHeatmap:
            AppStrings.localized("tasks.empty.title")
        }
    }

    var emptyStateDescription: String {
        switch self {
        case .pomodoro:
            AppStrings.localized("pomodoro.noTasks.description")
        case .inboxChildTaskParent:
            AppStrings.localized("inbox.route.childTask.emptyDescription")
        case .inboxChecklistTarget:
            AppStrings.localized("inbox.route.checklistItem.emptyDescription")
        case .todayHeatmap:
            AppStrings.localized("heatmap.picker.emptyDescription")
        }
    }
}
