import SwiftUI

struct TaskManagementRowAccessibilitySnapshot {
    let label: String
    let valueComponents: [String]

    var value: String {
        ListFormatter.localizedString(byJoining: valueComponents)
    }

    init(task: TaskNode, presentation: TaskManagementRowPresentation) {
        label = task.title

        var components: [String] = []
        if !presentation.path.isEmpty,
           presentation.path.localizedCaseInsensitiveCompare(task.title) != .orderedSame {
            components.append(presentation.path)
        }
        if presentation.isRunning {
            components.append(AppStrings.running)
        }
        components.append(
            String(
                format: AppStrings.localized("tasks.workedFormat"),
                DurationFormatter.compact(presentation.workedSeconds)
            )
        )
        if presentation.progress.totalCount > 0 {
            components.append(
                String(
                    format: AppStrings.localized("checklist.progressFormat"),
                    presentation.progress.completedCount,
                    presentation.progress.totalCount
                )
            )
        }
        if presentation.rollup?.isDisplayableForecast == true,
           let remainingSeconds = presentation.rollup?.remainingSeconds {
            components.append(
                String(
                    format: AppStrings.localized("forecast.remainingFormat"),
                    DurationFormatter.compact(remainingSeconds)
                )
            )
            if presentation.rollup?.projectedDays != nil,
               let projectedDaysText = presentation.rollup?.projectedDaysDisplayText {
                components.append(projectedDaysText)
            }
        }
        if presentation.childCount > 0 {
            components.append(
                String(
                    format: AppStrings.localized("tasks.childCount"),
                    presentation.childCount
                )
            )
        }
        valueComponents = components
    }
}

struct TaskManagementAccessibilityBody: View {
    let task: TaskNode
    let presentation: TaskManagementRowPresentation
    let showsNavigationChevron: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 10) {
                Text(task.title)
                    .font(.headline)
                    .lineLimit(nil)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)

                if showsNavigationChevron {
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.tertiary)
                        .padding(.top, 4)
                        .accessibilityHidden(true)
                }
            }

            if !presentation.path.isEmpty,
               presentation.path.localizedCaseInsensitiveCompare(task.title) != .orderedSame {
                Text(presentation.path)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(nil)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if presentation.isRunning {
                RunningStatusBadge()
            }

            Text(
                String(
                    format: AppStrings.localized("tasks.workedFormat"),
                    DurationFormatter.compact(presentation.workedSeconds)
                )
            )
            .font(.subheadline.monospacedDigit())
            .foregroundStyle(.secondary)

            if presentation.progress.totalCount > 0
                || presentation.rollup?.isDisplayableForecast == true {
                TaskProgressLine(progress: presentation.progress, rollup: presentation.rollup)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if presentation.childCount > 0 {
                Text(
                    String(
                        format: AppStrings.localized("tasks.childCount"),
                        presentation.childCount
                    )
                )
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(nil)
                .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.vertical, 8)
    }
}
