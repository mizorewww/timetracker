import SwiftUI

struct QuickStartTaskGroup: View {
    let tasks: [TaskNode]
    let store: TimeTrackerStore
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private var columns: [GridItem] {
        [GridItem(.adaptive(minimum: dynamicTypeSize.isAccessibilitySize ? 300 : 180), spacing: 12)]
    }

    var body: some View {
        LazyVGrid(columns: columns, spacing: 12) {
            ForEach(tasks, id: \.id) { task in
                let activeSegment = store.activeSegment(for: task.id)
                QuickStartTaskButton(
                    presentation: store.taskIdentityPresentation(for: task),
                    activeSegment: activeSegment,
                    command: store.timerPickerSelectionCommand(for: task),
                    openTask: {
                        store.openTaskDetail(task.id)
                    },
                    performTimerAction: {
                        if let activeSegment {
                            store.stop(segment: activeSegment)
                        } else {
                            store.performTimerPickerSelection(task)
                        }
                    }
                )
            }
        }
    }
}

private struct QuickStartTaskButton: View {
    let presentation: TaskIdentityPresentation
    let activeSegment: TimeSegment?
    let command: TimerPickerSelectionCommand
    let openTask: () -> Void
    let performTimerAction: () -> Void
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Button(action: openTask) {
                Group {
                    if dynamicTypeSize.isAccessibilitySize {
                        VStack(alignment: .leading, spacing: 8) {
                            taskIcon
                            taskTitle
                        }
                    } else {
                        HStack(spacing: 8) {
                            taskIcon
                            taskTitle
                        }
                    }
                }
                .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(presentation.title)
            .accessibilityValue(
                activeSegment == nil
                    ? (presentation.parentPath ?? "")
                    : AppStrings.localized("status.running")
            )
            .accessibilityHint(AppStrings.localized("tasks.openDetail"))
            .accessibilityIdentifier("home.quickStart.task.\(presentation.id.uuidString)")

            QuickStartTimerAction(
                taskID: presentation.id,
                taskTitle: presentation.title,
                taskColor: Color(hex: presentation.visual.colorHex) ?? .blue,
                activeSegment: activeSegment,
                command: command,
                action: performTimerAction
            )
        }
        .appCard(padding: 12)
    }

    private var taskIcon: some View {
        TaskIcon(visual: presentation.visual, size: 32)
    }

    private var taskTitle: some View {
        let text = presentation.text(for: .standard)
        return HStack(alignment: .top, spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text(text.primary)
                    .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 2)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                if let secondary = text.secondary {
                    Text(secondary)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 1)
                }
            }
            Spacer(minLength: 4)
            if activeSegment != nil {
                RunningStatusBadge()
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct QuickStartTimerAction: View {
    let taskID: UUID
    let taskTitle: String
    let taskColor: Color
    let activeSegment: TimeSegment?
    let command: TimerPickerSelectionCommand
    let action: () -> Void

    var body: some View {
        Button(role: activeSegment == nil ? nil : .destructive, action: action) {
            Label(actionTitle, systemImage: actionSystemImage)
                .lineLimit(1)
                .font(.callout.weight(.semibold))
                .frame(minHeight: 44)
        }
        .buttonStyle(.bordered)
        .tint(activeSegment == nil ? taskColor : .red)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityHint(accessibilityHint)
        .accessibilityIdentifier("home.quickStart.timer.\(taskID.uuidString)")
    }

    private var actionTitle: String {
        activeSegment == nil ? command.actionTitle : AppStrings.localized("timer.action.stop")
    }

    private var actionSystemImage: String {
        activeSegment == nil ? command.systemImage : "stop.fill"
    }

    private var accessibilityLabel: String {
        activeSegment == nil
            ? command.accessibilityLabel(for: taskTitle)
            : String(format: AppStrings.localized("timer.action.stopTaskFormat"), taskTitle)
    }

    private var accessibilityHint: String {
        activeSegment == nil
            ? command.accessibilityHint
            : AppStrings.localized("timer.task.stopHint")
    }
}
