import SwiftUI

private struct HomeTimerTaskPathText: View {
    let presentation: TaskBreadcrumbPresentation

    var body: some View {
        Group {
            if presentation.isRoot {
                Text(AppStrings.rootTask)
            } else if presentation.readable == presentation.abbreviated {
                Text(presentation.readable)
            } else {
                ViewThatFits(in: .horizontal) {
                    Text(presentation.readable)
                        .fixedSize(horizontal: true, vertical: false)
                    Text(presentation.abbreviated)
                }
            }
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .lineLimit(1)
        .truncationMode(.middle)
    }
}

struct HomeTimerTaskRow: View {
    let presentation: TaskIdentityPresentation
    let activeSegment: TimeSegment?
    let command: TimerPickerSelectionCommand
    let actionLabelStyle: TaskTimerActionLabelStyle
    let openTask: () -> Void
    let performTimerAction: () -> Void
    let taskAccessibilityIdentifier: String
    let actionAccessibilityIdentifier: String
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                accessibilityContent
            } else {
                standardContent
            }
        }
        .frame(minHeight: 44)
    }

    private var standardContent: some View {
        HStack(alignment: .center, spacing: 10) {
            taskButton(showsElapsedTime: true)

            TaskTimerActionButton(
                taskTitle: presentation.title,
                taskColor: Color(hex: presentation.visual.colorHex) ?? .blue,
                activeSegment: activeSegment,
                command: command,
                labelStyle: actionLabelStyle,
                action: performTimerAction,
                accessibilityIdentifier: actionAccessibilityIdentifier
            )
        }
    }

    private var accessibilityContent: some View {
        VStack(alignment: .leading, spacing: 10) {
            taskButton(showsElapsedTime: false)

            HStack(spacing: 12) {
                if let activeSegment {
                    elapsedTime(for: activeSegment)
                }
                Spacer(minLength: 0)
                TaskTimerActionButton(
                    taskTitle: presentation.title,
                    taskColor: Color(hex: presentation.visual.colorHex) ?? .blue,
                    activeSegment: activeSegment,
                    command: command,
                    labelStyle: actionLabelStyle,
                    action: performTimerAction,
                    accessibilityIdentifier: actionAccessibilityIdentifier
                )
            }
        }
    }

    private func taskButton(showsElapsedTime: Bool) -> some View {
        Button(action: openTask) {
            HStack(alignment: .center, spacing: 10) {
                TaskIcon(visual: presentation.visual, size: 34)

                VStack(alignment: .leading, spacing: 3) {
                    Text(presentation.title)
                        .font(.headline)
                        .foregroundStyle(.primary)
                        .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 1)
                        .minimumScaleFactor(0.82)
                        .fixedSize(
                            horizontal: false,
                            vertical: dynamicTypeSize.isAccessibilitySize
                        )

                    HomeTimerTaskPathText(presentation: presentation.breadcrumb)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .layoutPriority(1)

                if showsElapsedTime, let activeSegment {
                    elapsedTime(for: activeSegment)
                }
            }
            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(presentation.title)
        .accessibilityValue(
            activeSegment == nil
                ? (presentation.parentPath ?? "")
                : AppStrings.localized("status.running")
        )
        .accessibilityHint(AppStrings.localized("tasks.openDetail"))
        .accessibilityIdentifier(taskAccessibilityIdentifier)
    }

    private func elapsedTime(for segment: TimeSegment) -> some View {
        DurationLabel(startedAt: segment.startedAt, endedAt: segment.endedAt)
            .font(.title3.weight(.semibold))
            .monospacedDigit()
            .foregroundStyle(.primary)
            .lineLimit(1)
            .minimumScaleFactor(0.72)
            .frame(
                minWidth: 78,
                idealWidth: 88,
                maxWidth: 104,
                minHeight: 44,
                alignment: .trailing
            )
            .accessibilityIdentifier("home.timer.elapsed.\(segment.id.uuidString)")
    }
}

struct ActiveTimerRow: View {
    let store: TimeTrackerStore
    let segment: TimeSegment
    let actionLabelStyle: TaskTimerActionLabelStyle
    var openTaskDetail: ((UUID) -> Void)? = nil

    private var presentation: TaskIdentityPresentation {
        guard let task = store.task(for: segment.taskID) else {
            let title = store.displayTitle(for: segment)
            let parentPath = store.displayPath(for: segment)
            let fullPath = parentPath.isEmpty
                ? title
                : "\(parentPath) / \(title)"
            return TaskIdentityPresentation(
                id: segment.taskID,
                title: title,
                parentPath: parentPath,
                fullPath: fullPath,
                visual: TaskVisualPresentation(iconName: nil, colorHex: nil),
                breadcrumb: .root(title: title)
            )
        }
        return store.taskIdentityPresentation(for: task)
    }

    var body: some View {
        HomeTimerTaskRow(
            presentation: presentation,
            activeSegment: segment,
            command: .alreadyRunning,
            actionLabelStyle: actionLabelStyle,
            openTask: openTask,
            performTimerAction: {
                store.stop(segment: segment)
            },
            taskAccessibilityIdentifier: "home.activeTimer.task.\(segment.taskID.uuidString)",
            actionAccessibilityIdentifier: "home.timer.stop.\(segment.id.uuidString)"
        )
    }

    private func openTask() {
        if let openTaskDetail {
            openTaskDetail(segment.taskID)
        } else {
            store.openTaskDetail(segment.taskID)
        }
    }
}
