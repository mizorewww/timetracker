import Foundation
import SwiftData

/// Retires the deterministic catalog rows (workout/sleep tasks and their two
/// categories) seeded by the removed Apple Health integration.
///
/// The rows live in the main synced store as ordinary tasks/categories, so the
/// retirement goes through the repository command boundary with LWW-correct
/// markers and converges via CloudKit. The scan runs at every startup: it is
/// tolerate-absent, skips rows already retired, and writes nothing when no
/// legacy row is present. If an older health-capable build recreates a row,
/// the next launch of a current build retires it again.
enum AppleHealthCatalogCleanup {
    /// Deterministic IDs from the deleted `AppleHealthTaskCatalog`:
    /// `A1<namespace>0000-0000-4000-8000-0000000000<suffix>` with namespace
    /// 0x20 = task (suffix follows the workout/sleep order) and 0x10 =
    /// category (1 = exercise, 2 = daily).
    private static let legacyTaskIDs: [UUID] = [
        UUID(uuidString: "A1200000-0000-4000-8000-000000000001")!, // walking
        UUID(uuidString: "A1200000-0000-4000-8000-000000000002")!, // running
        UUID(uuidString: "A1200000-0000-4000-8000-000000000003")!, // cycling
        UUID(uuidString: "A1200000-0000-4000-8000-000000000004")!, // swimming
        UUID(uuidString: "A1200000-0000-4000-8000-000000000005")!, // strengthTraining
        UUID(uuidString: "A1200000-0000-4000-8000-000000000006")!, // highIntensityIntervalTraining
        UUID(uuidString: "A1200000-0000-4000-8000-000000000007")!, // yoga
        UUID(uuidString: "A1200000-0000-4000-8000-000000000008")!, // hiking
        UUID(uuidString: "A1200000-0000-4000-8000-000000000009")!, // rowing
        UUID(uuidString: "A1200000-0000-4000-8000-000000000010")!, // dance
        UUID(uuidString: "A1200000-0000-4000-8000-000000000011")!, // other workout
        UUID(uuidString: "A1200000-0000-4000-8000-000000000012")!, // sleep
    ]
    private static let legacyCategoryIDs: [UUID] = [
        UUID(uuidString: "A1100000-0000-4000-8000-000000000001")!, // exercise
        UUID(uuidString: "A1100000-0000-4000-8000-000000000002")!, // daily
    ]

    static func removeLegacyCatalogRowsIfNeeded(context: ModelContext) throws {
        let taskRepository = SwiftDataTaskRepository(context: context)

        var pendingTaskIDs: [UUID] = []
        for taskID in legacyTaskIDs {
            guard let task = try taskRepository.task(id: taskID),
                  task.deletedAt == nil,
                  task.archivedAt == nil
            else { continue }
            pendingTaskIDs.append(taskID)
        }
        var pendingCategoryIDs: [UUID] = []
        for categoryID in legacyCategoryIDs {
            guard let category = try taskRepository.category(id: categoryID),
                  category.deletedAt == nil
            else { continue }
            pendingCategoryIDs.append(categoryID)
        }
        guard pendingTaskIDs.isEmpty == false || pendingCategoryIDs.isEmpty == false else {
            return
        }

        // Never archive a task with live work; a stopped task is retired on a
        // later launch instead.
        let busyTaskIDs = try Set(
            SwiftDataTimeTrackingRepository(context: context)
                .activeSegments()
                .map(\.taskID)
        )
        for taskID in pendingTaskIDs where busyTaskIDs.contains(taskID) == false {
            try taskRepository.archiveTask(taskID: taskID)
        }
        for categoryID in pendingCategoryIDs {
            try taskRepository.softDeleteCategory(categoryID: categoryID)
        }
    }
}
