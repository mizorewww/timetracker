import Foundation
import OSLog

private enum WidgetSnapshotDiagnostics {
    static let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "me.mezorewww.timetracker",
        category: "WidgetSnapshot"
    )
}

extension TimeTrackerStore {
    @discardableResult
    func syncWidgetSnapshotIfAvailable(
        now: Date = Date(),
        cache: WidgetSnapshotCache? = nil
    ) -> Error? {
        let cache = cache ?? WidgetSnapshotCache()
        let activeTaskIDs = Set(activeSegments.map(\.taskID))
        let snapshot = WidgetSnapshotCache.snapshot(
            activeSegments: activeSegments,
            taskByID: taskByID,
            taskParentPathByID: taskParentPathByID,
            recentTasks: frequentRecentTasks(excluding: activeTaskIDs, limit: 3),
            todayGrossSeconds: todayGrossSeconds(now: now),
            todayWallSeconds: todayWallSeconds(now: now),
            generatedAt: now
        )
        do {
            try cache.save(snapshot)
            return nil
        } catch {
            errorMessage = String(
                format: AppStrings.localized("error.widgetSnapshotSaveFailed"),
                error.localizedDescription
            )
            WidgetSnapshotDiagnostics.logger.error(
                "Failed to save the widget snapshot: \(error.localizedDescription, privacy: .public)"
            )
            return error
        }
    }
}
