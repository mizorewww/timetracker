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

    /// Another device's clock can run ahead: a local write must still beat
    /// every row it observed for the task, tombstones included.
    @Test
    func settingACategoryBeatsANewerRemoteTombstoneForTheSameTask() throws {
        let context = try makeTestContext()
        let repository = SwiftDataTaskRepository(context: context, deviceID: "seed")
        let root = try repository.createTask(title: "Work", parentID: nil)
        let category = try repository.createCategory(title: "Career")
        let ahead = Date().addingTimeInterval(60)
        let remoteTombstone = TaskCategoryAssignment(
            taskID: root.id,
            categoryID: category.id,
            deviceID: "device-ahead"
        )
        remoteTombstone.updatedAt = ahead
        remoteTombstone.deletedAt = ahead
        context.insert(remoteTombstone)
        try context.save()

        try repository.setCategoryAssignment(categoryID: category.id, forRootTaskID: root.id)
        try context.save()

        #expect(try repository.categoryID(forRootTaskID: root.id) == category.id)
    }

    @Test
    func reusingALiveAssignmentBeatsANewerRemoteTombstoneRow() throws {
        let context = try makeTestContext()
        let repository = SwiftDataTaskRepository(context: context, deviceID: "seed")
        let career = try repository.createCategory(title: "Career")
        let health = try repository.createCategory(title: "Health")
        let root = try repository.createTask(title: "Work", parentID: nil, categoryID: career.id)
        let ahead = Date().addingTimeInterval(60)
        let remoteTombstone = TaskCategoryAssignment(
            taskID: root.id,
            categoryID: career.id,
            deviceID: "device-ahead"
        )
        remoteTombstone.updatedAt = ahead
        remoteTombstone.deletedAt = ahead
        context.insert(remoteTombstone)
        try context.save()

        try repository.setCategoryAssignment(categoryID: health.id, forRootTaskID: root.id)
        try context.save()

        #expect(try repository.categoryID(forRootTaskID: root.id) == health.id)
    }
}
