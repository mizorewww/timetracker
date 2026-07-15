import SwiftUI

struct PomodoroSetupSelectionControls: View {
    let store: TimeTrackerStore
    let selectedTask: TaskNode?
    let availableTasks: [TaskNode]
    let plans: [PomodoroPlan]
    @Binding var selectedPlanID: UUID?

    private var selectedPlan: PomodoroPlan? {
        plans.first { $0.id == selectedPlanID }
    }

    private var selectedTaskID: Binding<UUID?> {
        Binding(
            get: { store.selectedTaskID },
            set: { store.selectedTaskID = $0 }
        )
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
            Picker(selection: $selectedPlanID) {
                ForEach(plans) { plan in
                    Label(plan.displayName, systemImage: plan.iconName)
                        .tag(Optional(plan.id))
                }
            } label: {
                EmptyView()
            }
        } label: {
            PomodoroSelectionLabel(
                title: AppStrings.localized("pomodoro.choosePlan"),
                value: selectedPlan?.displayName ?? AppStrings.localized("common.choose"),
                systemImage: selectedPlan?.iconName ?? "slider.horizontal.3",
                tint: Color(hex: selectedPlan?.colorHex) ?? PomodoroStyle.accent
            )
            .appCard(padding: 14)
        }
        .menuIndicator(.hidden)
        .buttonStyle(.plain)
        .frame(maxWidth: .infinity)
        .accessibilityIdentifier("pomodoro.planPicker")
    }

    private var taskMenu: some View {
        Menu {
            Picker(selection: selectedTaskID) {
                ForEach(availableTasks, id: \.id) { task in
                    Label(store.path(for: task), systemImage: task.iconName ?? "checklist")
                        .tag(Optional(task.id))
                }
            } label: {
                EmptyView()
            }
        } label: {
            PomodoroSelectionLabel(
                title: AppStrings.localized("pomodoro.chooseTask"),
                value: selectedTask?.title ?? AppStrings.localized("common.choose"),
                systemImage: selectedTask?.iconName ?? "checklist",
                tint: Color(hex: selectedTask?.colorHex) ?? PomodoroStyle.accent
            )
            .appCard(padding: 14)
        }
        .menuIndicator(.hidden)
        .buttonStyle(.plain)
        .frame(maxWidth: .infinity)
        .accessibilityIdentifier("pomodoro.taskPicker")
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
                            .font(.body.weight(.semibold))
                            .foregroundStyle(.primary)
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
                            .font(.body.weight(.semibold))
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
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title)
        .accessibilityValue(value)
    }

    private var chevron: some View {
        Image(systemName: "chevron.up.chevron.down")
            .font(.caption2.weight(.semibold))
            .foregroundStyle(.secondary)
            .accessibilityHidden(true)
    }
}
