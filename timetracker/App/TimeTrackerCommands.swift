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
            .keyboardShortcut(shortcut(for: .addTime))
            .id(shortcutIdentity(for: .addTime))
            .accessibilityIdentifier("menu.shortcut.addTime")
            .accessibilityValue(shortcutDescription(for: .addTime))
            .disabled(store == nil || presentationRouter?.canPresent != true)
        }

        CommandMenu(AppStrings.localized("menu.task")) {
            Button(AppStrings.localized("menu.startSelectedTask")) {
                store?.startSelectedTask()
            }
            .keyboardShortcut(shortcut(for: .startSelectedTask))
            .id(shortcutIdentity(for: .startSelectedTask))
            .accessibilityIdentifier("menu.shortcut.startSelectedTask")
            .accessibilityValue(shortcutDescription(for: .startSelectedTask))
            .disabled(canTrackSelectedTask == false)

            Button(AppStrings.localized("menu.startPomodoro")) {
                store?.startPomodoroForSelectedTask()
            }
            .keyboardShortcut(shortcut(for: .startPomodoro))
            .id(shortcutIdentity(for: .startPomodoro))
            .accessibilityIdentifier("menu.shortcut.startPomodoro")
            .accessibilityValue(shortcutDescription(for: .startPomodoro))
            .disabled(canTrackSelectedTask == false)

            Divider()

            Button(AppStrings.localized("taskCategory.sort")) {
                guard let presentationRouter else { return }
                presentationRouter.presentTaskCategoryOrdering()
            }
            .disabled(
                (store?.taskCategories.count ?? 0) < 2 ||
                    presentationRouter?.canPresent != true
            )

            Divider()

            Button(AppStrings.localized("menu.archiveSelectedTask")) {
                guard let store, let selectedTask = store.selectedTask else {
                    return
                }
                store.archiveTaskProtectingUnsavedChanges(selectedTask.id)
            }
            .disabled(canArchiveSelectedTask == false)
        }

        CommandGroup(after: .sidebar) {
            Divider()

            destinationButton(.today, key: "1")
            destinationButton(.inbox, key: "2")
            destinationButton(.tasks, key: "3")
            destinationButton(.pomodoro, key: "4")
            destinationButton(.analytics, key: "5")

            Divider()

            Button(AppStrings.localized("menu.refreshData")) {
                store?.refreshQuietly()
            }
            .keyboardShortcut(shortcut(for: .refreshData))
            .id(shortcutIdentity(for: .refreshData))
            .accessibilityIdentifier("menu.shortcut.refreshData")
            .accessibilityValue(shortcutDescription(for: .refreshData))
            .disabled(store == nil)
        }
    }

    private func shortcut(
        for action: MacKeyboardShortcutAction
    ) -> KeyboardShortcut? {
        shortcutSettings.shortcut(for: action)?.toSwiftUI
    }

    private func shortcutIdentity(
        for action: MacKeyboardShortcutAction
    ) -> String {
        "\(action.rawValue)-\(shortcutSettings.revision)"
    }

    private func shortcutDescription(
        for action: MacKeyboardShortcutAction
    ) -> String {
        shortcutSettings.shortcut(for: action).map(String.init(describing:))
            ?? AppStrings.localized("settings.keyboardShortcuts.none")
    }

    private var canTrackSelectedTask: Bool {
        guard let store, let selectedTask = store.selectedTask else {
            return false
        }
        return store.isTaskAvailableForTracking(selectedTask)
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
        key: KeyEquivalent
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
        .keyboardShortcut(key, modifiers: [.command])
        .disabled(store == nil)
    }
}
#endif
