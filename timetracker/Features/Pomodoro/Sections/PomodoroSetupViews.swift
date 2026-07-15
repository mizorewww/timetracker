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

    private var taskColor: Color {
        Color(hex: selectedTask?.colorHex) ?? PomodoroStyle.accent
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                Spacer(minLength: 16)

                if availableTasks.isEmpty {
                    ContentUnavailableView {
                        Label(AppStrings.localized("pomodoro.noTasks.title"), systemImage: "timer")
                    } description: {
                        Text(.app("pomodoro.noTasks.description"))
                    } actions: {
                        Button(AppStrings.newTask) {
                            store.presentNewTask(preservingDestination: .pomodoro)
                        }
                        .buttonStyle(.borderedProminent)
                    }
                } else {
                    PomodoroTimerFace(
                        timeText: DurationFormatter.clock(plan.focusSeconds),
                        title: selectedTask?.title ?? AppStrings.localized("pomodoro.chooseTask"),
                        titleColor: taskColor
                    )

                    PomodoroSetupSelectionControls(
                        store: store,
                        selectedTask: selectedTask,
                        plans: availablePlans,
                        selectedPlanID: $selectedPlanID
                    )

                    Text(planSummary)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)

                    Button(action: startPomodoro) {
                        Label(AppStrings.localized("segment.start"), systemImage: "play.fill")
                            .font(.headline)
                            .frame(maxWidth: 260, minHeight: 44)
                    }
                    .controlSize(.large)
                    .buttonStyle(.borderedProminent)
                    .tint(taskColor)
                    .disabled(selectedTask == nil)
                    .accessibilityIdentifier("pomodoro.startFocus")
                }

                Spacer(minLength: 16)
            }
            .frame(maxWidth: 560)
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 24)
            .padding(.vertical, 20)
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

struct PomodoroTimerFace: View {
    let timeText: String
    let title: String
    let titleColor: Color

    var body: some View {
        VStack(spacing: 10) {
            Text(timeText)
                .font(.system(.largeTitle, design: .rounded, weight: .bold))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .foregroundStyle(PomodoroStyle.timerText)

            Text(title)
                .font(.title2.bold())
                .lineLimit(2)
                .multilineTextAlignment(.center)
                .foregroundStyle(titleColor)
        }
        .frame(maxWidth: .infinity, minHeight: 132)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(title)
        .accessibilityValue(timeText)
        .accessibilityIdentifier("pomodoro.timerFace")
    }
}

private struct PomodoroSetupSelectionControls: View {
    let store: TimeTrackerStore
    let selectedTask: TaskNode?
    let plans: [PomodoroPlan]
    @Binding var selectedPlanID: UUID?

    private var availableTasks: [TaskNode] {
        store.tasks.filter(store.isTaskAvailableForTracking)
    }

    private var selectedPlan: PomodoroPlan? {
        plans.first { $0.id == selectedPlanID }
    }

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 12) {
                planMenu
                taskMenu
            }
            VStack(spacing: 12) {
                planMenu
                taskMenu
            }
        }
    }

    private var planMenu: some View {
        Menu {
            ForEach(plans) { plan in
                Button {
                    selectedPlanID = plan.id
                } label: {
                    Label(plan.displayName, systemImage: plan.iconName)
                }
            }
        } label: {
            PomodoroSelectionLabel(
                title: AppStrings.localized("pomodoro.choosePlan"),
                value: selectedPlan?.displayName ?? AppStrings.localized("common.choose"),
                systemImage: selectedPlan?.iconName ?? "slider.horizontal.3",
                tint: Color(hex: selectedPlan?.colorHex) ?? PomodoroStyle.accent
            )
        }
        .buttonStyle(.bordered)
        .frame(maxWidth: .infinity)
    }

    private var taskMenu: some View {
        Menu {
            ForEach(availableTasks, id: \.id) { task in
                Button {
                    store.selectedTaskID = task.id
                } label: {
                    Label(store.path(for: task), systemImage: task.iconName ?? "checklist")
                }
            }
        } label: {
            PomodoroSelectionLabel(
                title: AppStrings.localized("pomodoro.chooseTask"),
                value: selectedTask?.title ?? AppStrings.localized("common.choose"),
                systemImage: selectedTask?.iconName ?? "checklist",
                tint: Color(hex: selectedTask?.colorHex) ?? PomodoroStyle.accent
            )
        }
        .buttonStyle(.bordered)
        .frame(maxWidth: .infinity)
    }
}

private struct PomodoroSelectionLabel: View {
    let title: String
    let value: String
    let systemImage: String
    let tint: Color
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: 6) {
                    Label {
                        Text(title)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } icon: {
                        Image(systemName: systemImage)
                            .foregroundStyle(tint)
                    }

                    HStack(alignment: .top, spacing: 8) {
                        Text(value)
                            .foregroundStyle(.primary)
                            .lineLimit(nil)
                            .fixedSize(horizontal: false, vertical: true)
                        Spacer(minLength: 4)
                        chevron
                    }
                }
            } else {
                HStack(spacing: 10) {
                    Image(systemName: systemImage)
                        .foregroundStyle(tint)
                        .frame(width: 24)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(title)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(value)
                            .foregroundStyle(.primary)
                            .lineLimit(1)
                    }
                    Spacer(minLength: 8)
                    chevron
                }
            }
        }
        .frame(maxWidth: .infinity, minHeight: 44)
        .contentShape(Rectangle())
    }

    private var chevron: some View {
        Image(systemName: "chevron.up.chevron.down")
            .font(.caption2.weight(.semibold))
            .foregroundStyle(.secondary)
            .accessibilityHidden(true)
    }
}
