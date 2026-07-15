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
        ScrollView {
            VStack(spacing: 24) {
                Spacer(minLength: 16)

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

                Spacer(minLength: 16)
            }
            .frame(maxWidth: 560)
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 24)
            .padding(.vertical, 20)
        }
    }
}
