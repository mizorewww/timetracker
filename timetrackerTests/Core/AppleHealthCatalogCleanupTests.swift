import Foundation
import SwiftData
import Testing
@testable import timetracker

@MainActor
struct AppleHealthCatalogCleanupTests {
    private let legacyTaskID = UUID(uuidString: "A1200000-0000-4000-8000-000000000012")! // sleep
    private let legacyCategoryID = UUID(uuidString: "A1100000-0000-4000-8000-000000000002")! // daily

    private func makeLegacyRows(in context: ModelContext) throws {
        let task = TaskNode(title: "Sleep", parentID: nil, deviceID: "seed")
        task.id = legacyTaskID
        let category = TaskCategory(title: "Daily", deviceID: "seed")
        category.id = legacyCategoryID
        let assignment = TaskCategoryAssignment(
            taskID: legacyTaskID,
            categoryID: legacyCategoryID,
            deviceID: "seed"
        )
        context.insert(task)
        context.insert(category)
        context.insert(assignment)
        try context.save()
    }

    @Test("cleanup archives legacy tasks and tombstones legacy categories")
    func cleanupRetiresLegacyRows() throws {
        let context = try makeTestContext()
        try makeLegacyRows(in: context)
        let ordinaryTask = TaskNode(title: "Mine", parentID: nil, deviceID: "seed")
        let ordinaryCategory = TaskCategory(title: "Mine", deviceID: "seed")
        context.insert(ordinaryTask)
        context.insert(ordinaryCategory)
        try context.save()

        try AppleHealthCatalogCleanup.removeLegacyCatalogRowsIfNeeded(context: context)

        let repository = SwiftDataTaskRepository(context: context)
        let retiredTask = try repository.task(id: legacyTaskID)
        #expect(retiredTask?.archivedAt != nil)
        #expect(try repository.category(id: legacyCategoryID) == nil)
        let assignments = try context.fetch(FetchDescriptor<TaskCategoryAssignment>())
        #expect(assignments.allSatisfy { $0.deletedAt != nil })
        let untouchedTask = try repository.task(id: ordinaryTask.id)
        #expect(untouchedTask?.archivedAt == nil)
        #expect(try repository.category(id: ordinaryCategory.id) != nil)
    }

    @Test("cleanup is a no-op when no legacy row needs retirement")
    func cleanupIsWriteIdempotent() throws {
        let context = try makeTestContext()
        try makeLegacyRows(in: context)
        try AppleHealthCatalogCleanup.removeLegacyCatalogRowsIfNeeded(context: context)

        let repository = SwiftDataTaskRepository(context: context)
        let markerBefore = try repository.task(id: legacyTaskID)?.clientMutationID

        try AppleHealthCatalogCleanup.removeLegacyCatalogRowsIfNeeded(context: context)

        #expect(try repository.task(id: legacyTaskID)?.clientMutationID == markerBefore)
    }

    @Test("cleanup tolerates stores that never contained the catalog")
    func cleanupToleratesAbsentRows() throws {
        let context = try makeTestContext()
        try AppleHealthCatalogCleanup.removeLegacyCatalogRowsIfNeeded(context: context)
        #expect(try context.fetch(FetchDescriptor<TaskNode>()).isEmpty)
    }

    @Test("cleanup skips a legacy task with a live segment for a later launch")
    func cleanupSkipsActiveWork() throws {
        let context = try makeTestContext()
        try makeLegacyRows(in: context)
        context.insert(TimeSegment(
            sessionID: UUID(),
            taskID: legacyTaskID,
            source: .timer,
            deviceID: "seed"
        ))
        try context.save()

        try AppleHealthCatalogCleanup.removeLegacyCatalogRowsIfNeeded(context: context)

        let repository = SwiftDataTaskRepository(context: context)
        #expect(try repository.task(id: legacyTaskID)?.archivedAt == nil)
        #expect(try repository.category(id: legacyCategoryID) == nil)
    }
}
