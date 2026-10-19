import Foundation
import SwiftData
import Testing
@testable import timetracker

/// Two devices can each create an assignment row for the same root task. The
/// newest row decides the task's category even when it is a tombstone.
@MainActor
struct TaskCategoryAssignmentSyncOrderTests {
    @Test
    func newerTombstonedAssignmentRowBeatsOlderActiveRowForTheSameTask() throws {
        let context = try makeTestContext()
        let repository = SwiftDataTaskRepository(context: context, deviceID: "seed")
        let root = try repository.createTask(title: "Work", parentID: nil)
        let olderCategory = try repository.createCategory(title: "Older")
        let newerCategory = try repository.createCategory(title: "Newer")
        let created = Date(timeIntervalSince1970: 1000)
        let removed = created.addingTimeInterval(60)

        let olderActiveRow = TaskCategoryAssignment(
            taskID: root.id,
            categoryID: olderCategory.id,
            deviceID: "device-a"
        )
        olderActiveRow.createdAt = created
        olderActiveRow.updatedAt = created
        let newerTombstoneRow = TaskCategoryAssignment(
            taskID: root.id,
            categoryID: newerCategory.id,
            deviceID: "device-b"
        )
        newerTombstoneRow.createdAt = created.addingTimeInterval(30)
        newerTombstoneRow.updatedAt = removed
        newerTombstoneRow.deletedAt = removed
        context.insert(olderActiveRow)
        context.insert(newerTombstoneRow)
        try context.save()

        #expect(try repository.categoryID(forRootTaskID: root.id) == nil)

        let store = makeTestStore()
        try store.configureIfNeeded(context: context)
        #expect(store.taskCategoryIDByRootTaskID[root.id] == nil)
        let storedRoot = try #require(store.taskByID[root.id])
        #expect(store.effectiveCategory(for: storedRoot) == nil)
    }
}
