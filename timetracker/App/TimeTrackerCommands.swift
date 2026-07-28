#if os(macOS)
import MacKeyboardShortcuts
import SwiftUI

struct TimeTrackerCommands: Commands {
    @FocusedValue(\.timeTrackerStore) private var store
    @FocusedValue(\.appPresentationRouter) private var presentationRouter
    let shortcutSettings: MacKeyboardShortcutSettings

    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            Button(AppStrings.newTask) {
                guard let store, let presentationRouter else { return }
                presentationRouter.presentNewTask(using: store)
            }
            .keyboardShortcut("n", modifiers: [.command])
            .accessibilityIdentifier("menu.shortcut.newTask")
            .disabled(store == nil || presentationRouter?.canPresent != true)

            Button(AppStrings.addTime) {
                guard let store, let presentationRouter else { return }
                presentationRouter.presentManualTime(using: store)
            }
            .timeTrackerShortcut(.addTime, settings: shortcutSettings)
            .disabled(store == nil || presentationRouter?.canPresent != true)
        }

        CommandMenu(AppStrings.localized("menu.task")) {
            Button(AppStrings.localized("menu.chooseTaskToStart")) {
                presentationRouter?.presentStartTaskPicker()
            }
            .timeTrackerShortcut(
                .chooseTaskToStart,
                settings: shortcutSettings
            )
            .disabled(canChooseTaskToStart == false)

            Button(AppStrings.localized("menu.startSelectedTask")) {
                store?.startSelectedTask()
            }
            .timeTrackerShortcut(
                .startSelectedTask,
                settings: shortcutSettings
            )
            .disabled(canStartSelectedTask == false)

            Button(AppStrings.localized("menu.stopSelectedTask")) {
                guard let store, let activeSelectedTaskSegment else { return }
                store.stop(segment: activeSelectedTaskSegment)
            }
            .timeTrackerShortcut(
                .stopSelectedTask,
                settings: shortcutSettings
            )
            .disabled(activeSelectedTaskSegment == nil)

            Button(AppStrings.localized("menu.startPomodoro")) {
                store?.startPomodoroForSelectedTask()
            }
            .timeTrackerShortcut(
                .startPomodoro,
                settings: shortcutSettings
            )
            .disabled(canTrackSelectedTask == false)

            Divider()

            Button(AppStrings.localized("menu.addSubtask")) {
                guard
                    let store,
                    let selectedTask = store.selectedTask,
                    let presentationRouter
                else {
                    return
                }
                presentationRouter.presentNewTask(
                    using: store,
                    parentID: selectedTask.id,
                    preservingDestination: store.desktopDestination
                )
            }
            .timeTrackerShortcut(.addSubtask, settings: shortcutSettings)
            .disabled(canAddSubtask == false)

            Button(AppStrings.localized("taskCategory.new")) {
                presentationRouter?.presentNewTaskCategory()
            }
            .timeTrackerShortcut(.newTaskCategory, settings: shortcutSettings)
            .disabled(presentationRouter?.canPresent != true)

            Button(AppStrings.localized("taskCategory.sort")) {
                guard let presentationRouter else { return }
                presentationRouter.presentTaskCategoryOrdering()
            }
            .timeTrackerShortcut(
                .sortTaskCategories,
                settings: shortcutSettings
            )
            .disabled(
                (store?.taskCategories.count ?? 0) < 2 ||
                    presentationRouter?.canPresent != true
            )

            Button(AppStrings.localized("aiTaskPlan.generateMenu")) {
                presentationRouter?.presentAITaskPlanGenerator()
            }
            .timeTrackerShortcut(.generateTaskPlan, settings: shortcutSettings)
            .disabled(
                store == nil || presentationRouter?.canPresent != true
            )

            Divider()

            Button(AppStrings.localized("menu.archiveSelectedTask")) {
                guard let store, let selectedTask = store.selectedTask else {
                    return
                }
                store.archiveTaskProtectingUnsavedChanges(selectedTask.id)
            }
            .timeTrackerShortcut(
                .archiveSelectedTask,
                settings: shortcutSettings
            )
            .disabled(canArchiveSelectedTask == false)
        }

        CommandGroup(after: .sidebar) {
            Divider()

            destinationButton(.today, action: .navigateToday)
            destinationButton(.inbox, action: .navigateInbox)
            destinationButton(.tasks, action: .navigateTasks)
            destinationButton(.pomodoro, action: .navigatePomodoro)
            destinationButton(.analytics, action: .navigateAnalytics)

            Divider()

            Button(AppStrings.localized("menu.refreshData")) {
                store?.refreshQuietly()
            }
            .timeTrackerShortcut(.refreshData, settings: shortcutSettings)
            .disabled(store == nil)
        }
    }

    private var canChooseTaskToStart: Bool {
        guard let store else { return false }
        return presentationRouter?.canPresent == true &&
            store.tasks.contains(where: store.isTaskAvailableForTracking)
    }

    private var canTrackSelectedTask: Bool {
        guard let store, let selectedTask = store.selectedTask else {
            return false
        }
        return store.isTaskAvailableForTracking(selectedTask)
    }

    private var canStartSelectedTask: Bool {
        guard let store, let selectedTask = store.selectedTask else {
            return false
        }
        return canTrackSelectedTask &&
            store.activeSegment(for: selectedTask.id) == nil
    }

    private var activeSelectedTaskSegment: TimeSegment? {
        guard let store, let selectedTask = store.selectedTask else {
            return nil
        }
        return store.activeSegment(for: selectedTask.id)
    }

    private var canAddSubtask: Bool {
        guard let store, let selectedTask = store.selectedTask else {
            return false
        }
        return store.isTaskEligibleAsParent(selectedTask) &&
            presentationRouter?.canPresent == true
    }

    private var canArchiveSelectedTask: Bool {
        guard let store, let selectedTask = store.selectedTask else {
            return false
        }
        return store.isTaskVisible(selectedTask) &&
            store.hasActiveTimer(inTaskSubtree: selectedTask.id) == false
    }

    private func destinationButton(
        _ destination: TimeTrackerStore.DesktopDestination,
        action: MacKeyboardShortcutAction
    ) -> some View {
        Button(destination.title) {
            guard let store else { return }
            store.taskDetailNavigationGuard.requestNavigation(
                dismissingActiveDetail: true
            ) { [weak store] in
                store?.closeTaskDetailNavigation()
                store?.desktopDestination = destination
            }
        }
        .timeTrackerShortcut(action, settings: shortcutSettings)
        .disabled(store == nil)
    }
}

private extension View {
    func timeTrackerShortcut(
        _ action: MacKeyboardShortcutAction,
        settings: MacKeyboardShortcutSettings
    ) -> some View {
        keyboardShortcut(settings.shortcut(for: action)?.toSwiftUI)
            .id("\(action.rawValue)-\(settings.revision)")
            .accessibilityIdentifier("menu.shortcut.\(action.rawValue)")
            .accessibilityValue(
                settings.shortcut(for: action).map(String.init(describing:))
                    ?? AppStrings.localized(
                        "settings.keyboardShortcuts.none"
                    )
            )
    }
}
#endif
