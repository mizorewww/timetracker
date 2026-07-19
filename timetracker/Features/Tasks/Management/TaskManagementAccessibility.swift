import Foundation

struct TaskManagementRowAccessibilitySnapshot {
    let label: String
    let valueComponents: [String]

    var value: String {
        ListFormatter.localizedString(byJoining: valueComponents)
    }

    init(task: TaskNode, presentation: TaskManagementRowPresentation) {
        label = task.title

        var components: [String] = []
        if presentation.identity.fullPath
            .localizedCaseInsensitiveCompare(task.title) != .orderedSame {
            components.append(presentation.identity.fullPath)
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
