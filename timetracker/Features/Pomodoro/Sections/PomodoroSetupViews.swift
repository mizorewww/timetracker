import SwiftUI

struct PomodoroSetupCard: View {
    let store: TimeTrackerStore
    let plan: PomodoroPlan
    let availablePlans: [PomodoroPlan]
    @Binding var selectedPlanID: UUID?

    private var selectedTask: TaskNode? {
        guard let task = store.selectedTaskID.flatMap({ store.task(for: $0) }),
              store.isTaskAvailableForTracking(task) else {
            return nil
        }
        return task
    }

    private var availableTasks: [TaskNode] {
        store.tasks.filter(store.isTaskAvailableForTracking)
    }

    var body: some View {
        PomodoroPageLayout {
            VStack(alignment: .leading, spacing: 24) {
                setupHeader
                if availableTasks.isEmpty {
                    PomodoroSetupEmptyState(store: store)
                } else {
                    PomodoroFocusSetupControls(
                        store: store,
                        plan: plan,
                        selectedTask: selectedTask,
                        availableTasks: availableTasks,
                        availablePlans: availablePlans,
                        selectedPlanID: $selectedPlanID
                    )
                }
            }
            .appCard(padding: 24)
            .accessibilityIdentifier("pomodoro.setup")
        } secondary: {
            PomodoroLedgerCard(store: store)
        }
    }

    private var setupHeader: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(AppStrings.localized("pomodoro.setup.title"), systemImage: "scope")
                .font(.title2.bold())

            Text(.app("pomodoro.setup.subtitle"))
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
