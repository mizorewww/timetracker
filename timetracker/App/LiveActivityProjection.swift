import Foundation

nonisolated struct LiveActivityTaskProjection: Equatable {
    let title: String
    let path: String
    let abbreviatedPath: String
    let iconName: String
    let colorHex: String
}

nonisolated struct LiveActivityProjectionService {
    static let maximumTitleUTF8Bytes = 512
    static let maximumPathUTF8Bytes = 768
    static let maximumIconUTF8Bytes = 128
    static let maximumColorUTF8Bytes = 16

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
                return $0.id < $1.id
            }
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
            title: SystemSurfaceTextBounds.boundedUTF8Prefix(
                presentation?.title ?? task?.title ?? fallbackTitle,
                maximumUTF8Bytes: Self.maximumTitleUTF8Bytes
            ),
            path: paths.readable,
            abbreviatedPath: paths.abbreviated,
            iconName: SystemSurfaceTextBounds.boundedUTF8Prefix(
                visual.symbolName,
                maximumUTF8Bytes: Self.maximumIconUTF8Bytes
            ),
            colorHex: SystemSurfaceTextBounds.boundedUTF8Prefix(
                visual.colorHex,
                maximumUTF8Bytes: Self.maximumColorUTF8Bytes
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
            SystemSurfaceTextBounds.boundedUTF8Prefix(
                readable,
                maximumUTF8Bytes: Self.maximumPathUTF8Bytes
            ),
            SystemSurfaceTextBounds.boundedUTF8Prefix(
                abbreviated,
                maximumUTF8Bytes: Self.maximumPathUTF8Bytes
            )
        )
    }
}
