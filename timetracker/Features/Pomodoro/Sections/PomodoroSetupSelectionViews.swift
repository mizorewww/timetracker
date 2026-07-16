import SwiftUI

struct PomodoroSetupSelectionControls: View {
    @Bindable var store: TimeTrackerStore
    let selectedTask: TaskNode?
    let availableTasks: [TaskNode]
    let plans: [PomodoroPlan]
    @Binding var selectedPlanID: UUID?

    private var selectedPlan: PomodoroPlan? {
        plans.first { $0.id == selectedPlanID }
    }

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 12) {
                planMenu.frame(minWidth: 220)
                taskMenu.frame(minWidth: 260)
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
                detail: nil,
                systemImage: selectedPlan?.iconName ?? "slider.horizontal.3",
                tint: Color(hex: selectedPlan?.colorHex) ?? PomodoroStyle.accent
            )
        }
        .menuIndicator(.hidden)
        .buttonStyle(.bordered)
        .controlSize(.large)
        .frame(maxWidth: .infinity)
        .accessibilityIdentifier("pomodoro.planPicker")
    }

    private var taskMenu: some View {
        Menu {
            Picker(selection: $store.selectedTaskID) {
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
                detail: selectedTask.flatMap(store.parentPath(for:)),
                systemImage: selectedTask?.iconName ?? "checklist",
                tint: Color(hex: selectedTask?.colorHex) ?? PomodoroStyle.accent
            )
        }
        .menuIndicator(.hidden)
        .buttonStyle(.bordered)
        .controlSize(.large)
        .frame(maxWidth: .infinity)
        .accessibilityIdentifier("pomodoro.taskPicker")
    }
}

private struct PomodoroSelectionLabel: View {
    let title: String
    let value: String
    let detail: String?
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
                        selectionValue
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
                        selectionValue
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

    private var selectionValue: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value)
                .font(.body.weight(.semibold))
                .foregroundStyle(.primary)
                .lineLimit(2)
                .multilineTextAlignment(.leading)
            if let detail, !detail.isEmpty {
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var chevron: some View {
        Image(systemName: "chevron.up.chevron.down")
            .font(.caption2.weight(.semibold))
            .foregroundStyle(.secondary)
            .accessibilityHidden(true)
    }
}
