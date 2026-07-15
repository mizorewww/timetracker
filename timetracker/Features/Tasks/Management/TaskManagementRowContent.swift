import SwiftUI

struct TaskManagementRowContent: View {
    let store: TimeTrackerStore
    let task: TaskNode
    let isRunning: Bool
    let showsNavigationChevron: Bool
#if os(iOS)
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
#endif

    var body: some View {
        #if os(iOS)
        if dynamicTypeSize.isAccessibilitySize {
            accessibilityBody
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
    private var accessibilityBody: some View {
        let progress = store.checklistProgress(for: task.id)
        let rollup = store.rollup(for: task.id)
        let childCount = store.children(of: task).count

        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 10) {
                TaskIcon(task: task, size: 30)

                Text(task.title)
                    .font(.headline)
                    .foregroundStyle(task.status == .completed ? .secondary : .primary)
                    .strikethrough(task.status == .completed)
                    .lineLimit(nil)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)

                if showsNavigationChevron {
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.tertiary)
                        .padding(.top, 4)
                }
            }

            VStack(alignment: .leading, spacing: 6) {
                statusMetadataBadge
                if isRunning {
                    RunningStatusBadge()
                }
            }

            if progress.totalCount > 0 {
                VStack(alignment: .leading, spacing: 5) {
                    ProgressView(value: progress.fraction)
                        .tint(Color(hex: task.colorHex) ?? .blue)
                    Text(String(format: AppStrings.localized("checklist.progressFormat"), progress.completedCount, progress.totalCount))
                        .font(.caption2.weight(.medium).monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }

            if rollup?.isDisplayableForecast == true {
                TaskProgressLine(progress: progress, rollup: rollup, showsChecklist: false)
                    .fixedSize(horizontal: false, vertical: true)
            }

            VStack(alignment: .leading, spacing: 3) {
                Text(.app("forecast.worked"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(DurationFormatter.compact(rollup?.workedSeconds ?? store.secondsForTaskTotalRollup(task)))
                    .font(.subheadline.monospacedDigit())

                if childCount > 0 {
                    Text(String(format: AppStrings.localized("tasks.childCount"), childCount))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(nil)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .padding(.vertical, 8)
    }

    @ViewBuilder
    private var regularBody: some View {
        let progress = store.checklistProgress(for: task.id)
        let rollup = store.rollup(for: task.id)
        HStack(spacing: 12) {
            TaskIcon(task: task, size: 30)

            VStack(alignment: .leading, spacing: 3) {
                Text(task.title)
                    .font(.headline)
                    .foregroundStyle(task.status == .completed ? .secondary : .primary)
                    .strikethrough(task.status == .completed)
                    .lineLimit(2)

                HStack(spacing: 6) {
                    Text(store.path(for: task))
                        .lineLimit(1)
                    statusMetadataBadge
                    if isRunning {
                        RunningStatusBadge()
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)

                if progress.totalCount > 0 || rollup?.isDisplayableForecast == true {
                    TaskProgressLine(progress: progress, rollup: rollup)
                }
            }

            Spacer(minLength: 10)

            VStack(alignment: .trailing, spacing: 3) {
                Text(DurationFormatter.compact(rollup?.workedSeconds ?? store.secondsForTaskTotalRollup(task)))
                    .font(.subheadline.monospacedDigit())
                    .foregroundStyle(.secondary)

                let childCount = store.children(of: task).count
                if childCount > 0 {
                    Text(String(format: AppStrings.localized("tasks.childCount"), childCount))
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
        let progress = store.checklistProgress(for: task.id)
        let rollup = store.rollup(for: task.id)
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
                    if isRunning {
                        RunningStatusBadge()
                    }
                }

                if progress.totalCount > 0 {
                    CompactChecklistProgressLine(
                        progress: progress,
                        tint: Color(hex: task.colorHex) ?? .blue
                    )
                }

                if rollup?.isDisplayableForecast == true {
                    TaskProgressLine(progress: progress, rollup: rollup, showsChecklist: false)
                        .lineLimit(2)
                }
            }

            Spacer(minLength: 8)

            VStack(alignment: .trailing, spacing: 3) {
                Text(DurationFormatter.compact(rollup?.workedSeconds ?? store.secondsForTaskTotalRollup(task)))
                    .font(.subheadline.monospacedDigit())
                    .foregroundStyle(.secondary)

                let childCount = store.children(of: task).count
                if childCount > 0 {
                    Text(String(format: AppStrings.localized("tasks.childCount"), childCount))
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
        if task.status != .completed && !store.isTaskAvailableForTracking(task) {
            TaskWorkBlockedStatusBadge()
        } else {
            TaskStatusBadge(status: task.status)
        }
    }
}
