import SwiftUI

struct TaskManagementRowPresentation {
    let path: String
    let progress: ChecklistProgress
    let rollup: TaskRollup?
    let workedSeconds: Int
    let childCount: Int
    let isAvailableForTracking: Bool
    let isRunning: Bool
}

struct TaskManagementRowContent: View {
    let task: TaskNode
    let presentation: TaskManagementRowPresentation
    let showsNavigationChevron: Bool
#if os(iOS)
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
#endif

    var body: some View {
        #if os(iOS)
        if dynamicTypeSize.isAccessibilitySize {
            TaskManagementAccessibilityBody(
                task: task,
                presentation: presentation,
                showsNavigationChevron: showsNavigationChevron
            )
        } else if TaskListLayoutPolicy(horizontalSizeClass: horizontalSizeClass).usesCompactRows {
            compactBody
        } else {
            regularBody
        }
        #else
        regularBody
        #endif
    }

    @ViewBuilder
    private var regularBody: some View {
        HStack(spacing: 12) {
            TaskIcon(task: task, size: 30)

            VStack(alignment: .leading, spacing: 3) {
                Text(task.title)
                    .font(.headline)
                    .foregroundStyle(task.status == .completed ? .secondary : .primary)
                    .strikethrough(task.status == .completed)
                    .lineLimit(2)

                HStack(spacing: 6) {
                    Text(presentation.path)
                        .lineLimit(1)
                    statusMetadataBadge
                    if presentation.isRunning {
                        RunningStatusBadge()
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)

                if presentation.progress.totalCount > 0
                    || presentation.rollup?.isDisplayableForecast == true {
                    TaskProgressLine(
                        progress: presentation.progress,
                        rollup: presentation.rollup
                    )
                }
            }

            Spacer(minLength: 10)

            VStack(alignment: .trailing, spacing: 3) {
                Text(DurationFormatter.compact(presentation.workedSeconds))
                    .font(.subheadline.monospacedDigit())
                    .foregroundStyle(.secondary)

                if presentation.childCount > 0 {
                    Text(
                        String(
                            format: AppStrings.localized("tasks.childCount"),
                            presentation.childCount
                        )
                    )
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }

            if showsNavigationChevron {
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.vertical, 4)
    }

    @ViewBuilder
    private var compactBody: some View {
        HStack(alignment: .center, spacing: 10) {
            TaskIcon(task: task, size: 30)

            VStack(alignment: .leading, spacing: 5) {
                Text(task.title)
                    .font(.headline)
                    .foregroundStyle(task.status == .completed ? .secondary : .primary)
                    .strikethrough(task.status == .completed)
                    .lineLimit(2)

                HStack(spacing: 6) {
                    statusMetadataBadge
                    if presentation.isRunning {
                        RunningStatusBadge()
                    }
                }

                if presentation.progress.totalCount > 0 {
                    CompactChecklistProgressLine(
                        progress: presentation.progress,
                        tint: Color(hex: task.colorHex) ?? .blue
                    )
                }

                if presentation.rollup?.isDisplayableForecast == true {
                    TaskProgressLine(
                        progress: presentation.progress,
                        rollup: presentation.rollup,
                        showsChecklist: false
                    )
                        .lineLimit(2)
                }
            }

            Spacer(minLength: 8)

            VStack(alignment: .trailing, spacing: 3) {
                Text(DurationFormatter.compact(presentation.workedSeconds))
                    .font(.subheadline.monospacedDigit())
                    .foregroundStyle(.secondary)

                if presentation.childCount > 0 {
                    Text(
                        String(
                            format: AppStrings.localized("tasks.childCount"),
                            presentation.childCount
                        )
                    )
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }

                if showsNavigationChevron {
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.tertiary)
                }
            }
        }
        .padding(.vertical, 6)
    }

    @ViewBuilder
    private var statusMetadataBadge: some View {
        if task.status != .completed && !presentation.isAvailableForTracking {
            TaskWorkBlockedStatusBadge()
        } else if task.status != .active {
            TaskStatusBadge(status: task.status)
        }
    }

}
