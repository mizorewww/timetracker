import SwiftUI

struct PomodoroSetupCard: View {
    let store: TimeTrackerStore
    let plan: PomodoroPlan
    let availablePlans: [PomodoroPlan]
    @Binding var selectedPlanID: UUID?
    @Binding var focusTaskID: UUID?
    let selectFocusTask: () -> Void
    #if os(iOS)
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    #endif

    private var selectedTask: TaskNode? {
        guard let task = focusTaskID.flatMap({ store.task(for: $0) }),
              store.isTaskAvailableForTracking(task) else {
            return nil
        }
        return task
    }

    private var availableTasks: [TaskNode] {
        store.tasks.filter(store.isTaskAvailableForTracking)
    }

    var body: some View {
        let layout = PomodoroLayoutPolicy(horizontalSizeClass: effectiveHorizontalSizeClass)
        PomodoroPageLayout {
            VStack(alignment: .leading, spacing: layout.setupSectionSpacing) {
                setupHeader
                if availableTasks.isEmpty {
                    PomodoroSetupEmptyState(store: store)
                } else {
                    PomodoroFocusSetupControls(
                        store: store,
                        plan: plan,
                        selectedTask: selectedTask,
                        availablePlans: availablePlans,
                        selectedPlanID: $selectedPlanID,
                        focusTaskID: $focusTaskID,
                        selectFocusTask: selectFocusTask,
                        contentSpacing: layout.setupSectionSpacing
                    )
                }
            }
            .appCard(padding: layout.setupCardPadding)
        } secondary: {
            PomodoroLedgerCard(store: store)
        }
    }

    private var effectiveHorizontalSizeClass: UserInterfaceSizeClass? {
        #if os(iOS)
        horizontalSizeClass
        #else
        nil
        #endif
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
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("pomodoro.setup")
    }
}
