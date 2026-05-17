import SwiftUI

struct PomodoroSetupCard: View {
    @ObservedObject var store: TimeTrackerStore
    let plan: PomodoroPlan
    let availablePlans: [PomodoroPlan]
    @Binding var selectedPlanID: UUID?
    let displayedFocusSecondsOverride: Int?
    let rendersTimerContent: Bool

    private var selectedTask: TaskNode? {
        store.selectedTaskID.flatMap { store.task(for: $0) }
    }

    private var availableTasks: [TaskNode] {
        store.tasks.filter { $0.deletedAt == nil && $0.status != .archived }
    }

    private var accent: Color {
        PomodoroStyle.accent
    }

    private var taskColor: Color {
        Color(hex: selectedTask?.colorHex) ?? accent
    }

    var body: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 40)

            PomodoroSelectableTimerFace(
                store: store,
                tasks: availableTasks,
                plans: availablePlans,
                selectedPlanID: $selectedPlanID,
                timeText: DurationFormatter.clock(displayedFocusSeconds),
                title: selectedTask?.title ?? AppStrings.localized("pomodoro.chooseTask"),
                titleColor: taskColor,
                rendersContent: rendersTimerContent
            )
            .pomodoroTimerFaceSource(.setup)

            Spacer(minLength: 72)

            Button {
                startPomodoro()
            } label: {
                Label(AppStrings.localized("segment.start"), systemImage: "play.fill")
                    .font(.body)
            }
            .controlSize(.large)
            .buttonStyle(.borderedProminent)
            .tint(accent)
            .disabled(selectedTask == nil)
            .accessibilityIdentifier("pomodoro.startFocus")

            Text(.app("pomodoro.tapTimeToChoosePreset"))
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.top, 10)

            Spacer(minLength: 40)
        }
        .padding(.horizontal, 24)
        .frame(maxWidth: .infinity)
    }

    private var displayedFocusSeconds: Int {
        displayedFocusSecondsOverride ?? plan.focusSeconds
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
        VStack(spacing: 0) {
            Text(timeText)
                .font(.system(size: 96, weight: .bold, design: .rounded))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.56)
                .frame(height: 116)
                .foregroundStyle(PomodoroStyle.timerText)

            Text(title)
                .font(.system(size: 36, weight: .bold, design: .rounded))
                .lineLimit(1)
                .minimumScaleFactor(0.64)
                .foregroundStyle(titleColor)
                .frame(height: 50)
        }
        .frame(width: 255)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("pomodoro.timerFace")
    }
}

private struct PomodoroSelectableTimerFace: View {
    @ObservedObject var store: TimeTrackerStore
    let tasks: [TaskNode]
    let plans: [PomodoroPlan]
    @Binding var selectedPlanID: UUID?
    let timeText: String
    let title: String
    let titleColor: Color
    let rendersContent: Bool
    @State private var isTaskPickerPresented = false
    @State private var isPlanPickerPresented = false

    var body: some View {
        VStack(spacing: 0) {
            Button {
                isPlanPickerPresented = true
            } label: {
                Text(timeText)
                    .font(.system(size: 96, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.56)
                    .frame(width: 255, height: 116)
                    .foregroundStyle(rendersContent ? PomodoroStyle.timerText : Color.clear)
            }
            .buttonStyle(.plain)
            .contentShape(Rectangle())
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(AppStrings.localized("pomodoro.choosePlan"))
            .accessibilityIdentifier("pomodoro.choosePlan")
            .accessibilityAddTraits(.isButton)
            .popover(isPresented: $isPlanPickerPresented, attachmentAnchor: .rect(.bounds), arrowEdge: .top) {
                planPopoverContent
            }

            Button {
                isTaskPickerPresented = true
            } label: {
                Text(title)
                    .font(.system(size: 36, weight: .bold, design: .rounded))
                    .lineLimit(1)
                    .minimumScaleFactor(0.64)
                    .foregroundStyle(rendersContent ? titleColor : Color.clear)
                    .frame(width: 255, height: 50)
            }
            .buttonStyle(.plain)
            .contentShape(Rectangle())
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(AppStrings.localized("pomodoro.chooseTask"))
            .accessibilityIdentifier("pomodoro.chooseTask")
            .accessibilityAddTraits(.isButton)
            .popover(isPresented: $isTaskPickerPresented, attachmentAnchor: .rect(.bounds), arrowEdge: .top) {
                taskPopoverContent
            }
        }
        .frame(width: 255)
        .accessibilityElement(children: .contain)
    }

    private var taskPopoverContent: some View {
        ScrollView {
            VStack(spacing: 0) {
                ForEach(tasks, id: \.id) { task in
                    let taskColor = Color(hex: task.colorHex) ?? PomodoroStyle.accent
                    Button {
                        store.selectTask(task.id, revealInToday: false)
                        isTaskPickerPresented = false
                    } label: {
                        HStack(spacing: 12) {
                            TaskIcon(task: task, size: 28)
                            Text(store.path(for: task))
                                .font(.body)
                                .foregroundStyle(.primary)
                                .lineLimit(1)
                            Spacer(minLength: 12)
                            if store.selectedTaskID == task.id {
                                Image(systemName: "checkmark")
                                    .font(.body.weight(.semibold))
                                    .foregroundStyle(taskColor)
                            }
                        }
                        .padding(.horizontal, 14)
                        .frame(height: 48)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("pomodoro.task.\(task.title)")

                    if task.id != tasks.last?.id {
                        Divider().padding(.leading, 54)
                    }
                }
            }
            .padding(.vertical, 8)
        }
        .frame(width: 320, height: popoverHeight(for: tasks.count))
        .settingsPopoverAdaptation()
    }

    private var planPopoverContent: some View {
        ScrollView {
            VStack(spacing: 0) {
                ForEach(plans.indices, id: \.self) { index in
                    let plan = plans[index]
                    let planColor = Color(hex: plan.colorHex) ?? PomodoroStyle.accent
                    Button {
                        selectedPlanID = plan.id
                        isPlanPickerPresented = false
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: plan.iconName)
                                .font(.body.weight(.semibold))
                                .foregroundStyle(planColor)
                                .frame(width: 28, height: 28)
                            Text(plan.displayName)
                                .font(.body)
                                .foregroundStyle(.primary)
                                .lineLimit(1)
                            Spacer(minLength: 12)
                            if selectedPlanID == plan.id {
                                Image(systemName: "checkmark")
                                    .font(.body.weight(.semibold))
                                    .foregroundStyle(planColor)
                            }
                        }
                        .padding(.horizontal, 14)
                        .frame(height: 48)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("pomodoro.plan.\(index)")

                    if plan.id != plans.last?.id {
                        Divider().padding(.leading, 54)
                    }
                }
            }
            .padding(.vertical, 8)
        }
        .frame(width: 280, height: popoverHeight(for: plans.count))
        .settingsPopoverAdaptation()
    }

    private func popoverHeight(for count: Int) -> CGFloat {
        min(CGFloat(max(count, 1)) * 48 + 16, 360)
    }
}
