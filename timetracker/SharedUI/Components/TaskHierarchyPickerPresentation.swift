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
        case .singleSelection:
            AppStrings.localized("pomodoro.chooseTask")
        }
    }

    var accessibilityIdentifier: String {
        switch mode {
        case .timer:
            "timer.taskPicker"
        case .singleSelection:
            "pomodoro.taskPicker"
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
        case .singleSelection:
            return AppStrings.localized("pomodoro.noTasks.title")
        }
    }

    func emptyStateDescription(
        _ projection: TaskHierarchyProjection
    ) -> String {
        if projection.hasVisibleTasks {
            return AppStrings.localized("timer.search.empty.description")
        }
        switch mode {
        case .timer:
            return AppStrings.localized("tasks.empty.description")
        case .singleSelection:
            return AppStrings.localized("pomodoro.noTasks.description")
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

extension TimerPickerMode {
    var title: String {
        switch self {
        case .start:
            AppStrings.startTimer
        case .startAnother:
            AppStrings.localized("home.startAnotherTimer")
        case .switchTimer:
            AppStrings.localized("home.switchTimer")
        }
    }

    var systemImage: String {
        switch self {
        case .start:
            "play.fill"
        case .startAnother:
            "plus"
        case .switchTimer:
            "arrow.left.arrow.right"
        }
    }

    var footer: LocalizedStringKey {
        switch self {
        case .start:
            .app("timer.picker.startFooter")
        case .startAnother:
            .app("timer.picker.parallelFooter")
        case .switchTimer:
            .app("timer.picker.switchFooter")
        }
    }
}

extension TimerPickerSelectionCommand {
    var actionTitle: String {
        switch self {
        case .alreadyRunning:
            AppStrings.running
        case .start:
            AppStrings.localized("timer.picker.action.start")
        case .switchTimer:
            AppStrings.localized("timer.picker.action.switch")
        }
    }

    var systemImage: String {
        switch self {
        case .alreadyRunning:
            "checkmark"
        case .start:
            "play.fill"
        case .switchTimer:
            "arrow.left.arrow.right"
        }
    }

    var accessibilityHint: String {
        switch self {
        case .alreadyRunning:
            AppStrings.localized("timer.picker.runningHint")
        case .start:
            AppStrings.localized("timer.task.startHint")
        case .switchTimer:
            AppStrings.localized("timer.task.switchHint")
        }
    }

    func accessibilityLabel(for taskTitle: String) -> String {
        let key = switch self {
        case .alreadyRunning:
            "timer.picker.runningTaskFormat"
        case .start:
            "timer.picker.startTaskFormat"
        case .switchTimer:
            "timer.picker.switchTaskFormat"
        }
        return String(format: AppStrings.localized(key), taskTitle)
    }
}
