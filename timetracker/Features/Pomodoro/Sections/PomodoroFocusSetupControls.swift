import SwiftUI

struct PomodoroFocusSetupControls: View {
    let store: TimeTrackerStore
    let plan: PomodoroPlan
    let selectedTask: TaskNode?
    let availableTasks: [TaskNode]
    let availablePlans: [PomodoroPlan]
    @Binding var selectedPlanID: UUID?

    private var taskColor: Color {
        Color(hex: selectedTask?.colorHex) ?? PomodoroStyle.accent
    }

    var body: some View {
        VStack(spacing: 24) {
            PomodoroTimerFace(
                timeText: DurationFormatter.clock(plan.focusSeconds),
                title: selectedTask?.title ?? AppStrings.localized("pomodoro.chooseTask"),
                titleColor: taskColor
            )

            PomodoroSetupSelectionControls(
                store: store,
                selectedTask: selectedTask,
                availableTasks: availableTasks,
                plans: availablePlans,
                selectedPlanID: $selectedPlanID
            )

            Text(planSummary)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)

            Button(action: startPomodoro) {
                Label(AppStrings.localized("segment.start"), systemImage: "play.fill")
                    .font(.headline)
                    .frame(maxWidth: .infinity, minHeight: 44)
            }
            .controlSize(.large)
            .buttonStyle(.borderedProminent)
            .tint(taskColor)
            .frame(maxWidth: 320)
            .disabled(selectedTask == nil)
            .accessibilityIdentifier("pomodoro.startFocus")
        }
    }

    private var planSummary: String {
        let focus = String(format: AppStrings.localized("common.minutes"), plan.focusMinutes)
        let shortBreak = String(format: AppStrings.localized("common.minutes"), plan.shortBreakMinutes)
        return String(
            format: AppStrings.localized("pomodoro.planSummary"),
            focus,
            shortBreak,
            plan.rounds
        )
    }

    private func startPomodoro() {
        store.startPomodoroForSelectedTask(
            focusSeconds: plan.focusSeconds,
            breakSeconds: plan.shortBreakSeconds,
            longBreakSeconds: plan.longBreakSeconds,
            targetRounds: plan.rounds
        )
    }
}
