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

    private var taskPath: String {
        selectedTask.map(store.path(for:)) ?? AppStrings.localized("pomodoro.chooseTask")
    }

    var body: some View {
        VStack(spacing: 24) {
            PomodoroTimerFace(
                timeText: DurationFormatter.clock(plan.focusSeconds),
                title: selectedTask?.title ?? AppStrings.localized("pomodoro.chooseTask"),
                subtitle: selectedTask.flatMap(store.parentPath(for:)),
                titleColor: taskColor,
                spokenLabel: taskPath,
                spokenValue: String(
                    format: AppStrings.localized("pomodoro.focusDuration.accessibility"),
                    DurationFormatter.clock(plan.focusSeconds)
                )
            )

            PomodoroSetupSelectionControls(
                store: store,
                selectedTask: selectedTask,
                availableTasks: availableTasks,
                plans: availablePlans,
                selectedPlanID: $selectedPlanID
            )

            PomodoroPlanDetails(plan: plan)

            Button(action: startPomodoro) {
                Label(AppStrings.localized("pomodoro.startFocus"), systemImage: "play.fill")
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

    private func startPomodoro() {
        store.startPomodoroForSelectedTask(
            focusSeconds: plan.focusSeconds,
            breakSeconds: plan.shortBreakSeconds,
            longBreakSeconds: plan.longBreakSeconds,
            targetRounds: plan.rounds
        )
    }
}

private struct PomodoroPlanDetails: View {
    let plan: PomodoroPlan

    var body: some View {
        Grid(horizontalSpacing: 24, verticalSpacing: 16) {
            GridRow {
                metric("pomodoro.focus", value: minutes(plan.focusMinutes))
                metric("pomodoro.shortBreak", value: minutes(plan.shortBreakMinutes))
            }
            GridRow {
                metric("pomodoro.longBreak", value: minutes(plan.longBreakMinutes))
                metric("pomodoro.rounds", value: String(plan.rounds))
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 4)
        .accessibilityIdentifier("pomodoro.planDetails")
    }

    private func metric(_ key: String, value: String) -> some View {
        VStack(spacing: 3) {
            Text(value)
                .font(.body.weight(.semibold))
                .foregroundStyle(.primary)
            Text(.app(key))
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, alignment: .top)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(AppStrings.localized(key))
        .accessibilityValue(value)
    }

    private func minutes(_ value: Int) -> String {
        String(format: AppStrings.localized("common.minutes"), value)
    }
}
