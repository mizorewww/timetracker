import Foundation

nonisolated struct LiveActivityTaskProjection: Equatable {
    let title: String
    let path: String
    let abbreviatedPath: String
    let iconName: String
    let colorHex: String
}

nonisolated struct LiveActivityProjectionService {
    func primarySegment(
        from activeSegments: [TimeSegment],
        now: Date
    ) -> TimeSegment? {
        activeSegments
            .filter { $0.deletedAt == nil && $0.startedAt <= now }
            .min {
                if $0.startedAt != $1.startedAt {
                    return $0.startedAt < $1.startedAt
                }
                return $0.id.uuidString < $1.id.uuidString
            }
    }

    func taskProjection(
        taskID: UUID,
        tasks: [TaskNode],
        fallbackTitle: String
    ) -> LiveActivityTaskProjection {
        taskProjection(
            taskID: taskID,
            indexes: TaskTreeService().indexes(tasks: tasks),
            fallbackTitle: fallbackTitle
        )
    }

    func taskProjection(
        taskID: UUID,
        indexes: TaskTreeIndexes,
        fallbackTitle: String
    ) -> LiveActivityTaskProjection {
        let task = indexes.taskByID[taskID]
        let presentation = indexes.taskIdentityPresentation(for: taskID)
        let visual = presentation?.visual ?? TaskVisualPresentation(
            iconName: task?.iconName ?? "timer",
            colorHex: task?.colorHex ?? "0A84FF"
        )
        let paths = projectedPaths(for: presentation)

        return LiveActivityTaskProjection(
            title: bounded(
                presentation?.title ?? task?.title ?? fallbackTitle,
                maximumUTF8Bytes: LiveActivityProjectionLimits.maximumTitleUTF8Bytes
            ),
            path: paths.readable,
            abbreviatedPath: paths.abbreviated,
            iconName: bounded(
                visual.symbolName,
                maximumUTF8Bytes: LiveActivityProjectionLimits.maximumIconUTF8Bytes
            ),
            colorHex: bounded(
                visual.colorHex,
                maximumUTF8Bytes: LiveActivityProjectionLimits.maximumColorUTF8Bytes
            )
        )
    }

    private func projectedPaths(
        for presentation: TaskIdentityPresentation?
    ) -> (readable: String, abbreviated: String) {
        let defaultPath = AppStrings.localized("live.timer.defaultPath")
        let readable: String
        let abbreviated: String
        if let presentation {
            readable = presentation.breadcrumb.isRoot
                ? AppStrings.rootTask
                : presentation.breadcrumb.readable
            abbreviated = presentation.breadcrumb.isRoot
                ? AppStrings.rootTask
                : presentation.breadcrumb.abbreviated
        } else {
            readable = defaultPath
            abbreviated = defaultPath
        }
        return (
            bounded(
                readable,
                maximumUTF8Bytes: LiveActivityProjectionLimits.maximumPathUTF8Bytes
            ),
            bounded(
                abbreviated,
                maximumUTF8Bytes: LiveActivityProjectionLimits.maximumPathUTF8Bytes
            )
        )
    }

    private func bounded(
        _ value: String,
        maximumUTF8Bytes: Int
    ) -> String {
        LiveActivityProjectionLimits.boundedUTF8Prefix(
            value,
            maximumUTF8Bytes: maximumUTF8Bytes
        )
    }
}
