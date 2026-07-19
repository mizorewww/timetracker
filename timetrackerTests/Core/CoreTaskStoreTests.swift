import Foundation
import Observation
import SwiftData
import Testing
@testable import timetracker

@Suite(.serialized)
struct CoreTaskStoreTests {
    @Test @MainActor
    func legacyArchiveMarkersDriveLifecycleWhileOtherRawValuesStayInert() {
        let timestampArchived = TaskNode(
            title: "Timestamp archived",
            parentID: nil,
            deviceID: "test"
        )
        timestampArchived.statusRaw = LegacyTaskStatusRaw.active
        timestampArchived.archivedAt = Date(timeIntervalSinceReferenceDate: 100)
        let timestampArchivedChild = TaskNode(
            title: "Timestamp archived child",
            parentID: timestampArchived.id,
            deviceID: "test"
        )

        let rawArchived = TaskNode(
            title: "Raw archived",
            parentID: nil,
            deviceID: "test"
        )
        rawArchived.statusRaw = LegacyTaskStatusRaw.archived
        rawArchived.archivedAt = nil
        let rawArchivedChild = TaskNode(
            title: "Raw archived child",
            parentID: rawArchived.id,
            deviceID: "test"
        )

        let completed = TaskNode(title: "Completed", parentID: nil, deviceID: "test")
        completed.statusRaw = LegacyTaskStatusRaw.completed
        let completedChild = TaskNode(
            title: "Completed child",
            parentID: completed.id,
            deviceID: "test"
        )
        let planned = TaskNode(title: "Planned", parentID: nil, deviceID: "test")
        planned.statusRaw = LegacyTaskStatusRaw.planned
        let tasks = [
            timestampArchived,
            timestampArchivedChild,
            rawArchived,
            rawArchivedChild,
            completed,
            completedChild,
            planned,
        ]

        #expect(timestampArchived.statusRaw == LegacyTaskStatusRaw.active)
        #expect(timestampArchived.isArchivedForLifecycle)
        #expect(rawArchived.archivedAt == nil)
        #expect(rawArchived.isArchivedForLifecycle)
        #expect(completed.isArchivedForLifecycle == false)
        #expect(planned.isArchivedForLifecycle == false)

        let availability = TaskTrackingAvailabilityService()
        let eligibility = availability.eligibility(tasks: tasks)
        #expect(
            eligibility.visibleTaskIDs ==
                Set([completed.id, completedChild.id, planned.id])
        )
        #expect(
            eligibility.trackableTaskIDs ==
                Set([completed.id, completedChild.id, planned.id])
        )
        #expect(availability.parentChangeBlocker(for: timestampArchived) == .archived)
        #expect(availability.parentChangeBlocker(for: rawArchived) == .archived)
        #expect(availability.parentChangeBlocker(for: completed) == nil)
        #expect(availability.parentChangeBlocker(for: planned) == nil)

        let store = makeTestStore()
        store.tasks = tasks
        #expect(
            Set(store.archivedTasks.map(\.id)) ==
                Set([timestampArchived.id, rawArchived.id])
        )
    }

    @Test
    func taskEligibilityHidesOnlyArchivedAndDeletedBranches() {
        let archivedRoot = TaskNode(title: "Archived", parentID: nil, deviceID: "test")
        archivedRoot.statusRaw = LegacyTaskStatusRaw.archived
        let child = TaskNode(title: "Child", parentID: archivedRoot.id, deviceID: "test")
        let grandchild = TaskNode(title: "Grandchild", parentID: child.id, deviceID: "test")
        let availableRoot = TaskNode(title: "Available", parentID: nil, deviceID: "test")
        let deletedRoot = TaskNode(title: "Deleted", parentID: nil, deviceID: "test")
        deletedRoot.deletedAt = Date()
        let deletedDescendant = TaskNode(title: "Hidden descendant", parentID: deletedRoot.id, deviceID: "test")
        let completedRoot = TaskNode(title: "Completed", parentID: nil, deviceID: "test")
        completedRoot.statusRaw = LegacyTaskStatusRaw.completed
        let completedChild = TaskNode(title: "Ordinary child", parentID: completedRoot.id, deviceID: "test")

        let eligibility = TaskTrackingAvailabilityService().eligibility(
            tasks: [
                archivedRoot,
                child,
                grandchild,
                availableRoot,
                deletedRoot,
                deletedDescendant,
                completedRoot,
                completedChild
            ]
        )

        #expect(eligibility.visibleTaskIDs == Set([availableRoot.id, completedRoot.id, completedChild.id]))
        #expect(eligibility.trackableTaskIDs == eligibility.visibleTaskIDs)
        #expect(child.statusRaw == LegacyTaskStatusRaw.active)
        #expect(grandchild.statusRaw == LegacyTaskStatusRaw.active)
        #expect(completedChild.statusRaw == LegacyTaskStatusRaw.active)

        let availabilityService = TaskTrackingAvailabilityService()
        #expect(availabilityService.parentChangeBlocker(for: archivedRoot) == .archived)
        #expect(availabilityService.parentChangeBlocker(for: deletedRoot) == .deleted)
        #expect(availabilityService.parentChangeBlocker(for: completedRoot) == nil)
        #expect(availabilityService.parentChangeBlocker(for: completedChild) == nil)

        let treeService = TaskTreeService()
        let candidates = treeService.validParentTasks(
            for: completedChild.id,
            tasks: [
                archivedRoot,
                child,
                grandchild,
                availableRoot,
                deletedRoot,
                deletedDescendant,
                completedRoot,
                completedChild
            ]
        )
        #expect(Set(candidates.map(\.id)) == Set([availableRoot.id, completedRoot.id]))
        #expect(treeService.canMove(
            taskID: completedChild.id,
            to: availableRoot.id,
            tasks: [completedRoot, completedChild, availableRoot]
        ))
    }

    @Test @MainActor
    func archivedSettingsKeepsNestedExplicitArchivesVisibleAndRequiresParentFirst() {
        let parent = TaskNode(title: "Archived parent", parentID: nil, deviceID: "test")
        parent.archivedAt = Date(timeIntervalSinceReferenceDate: 100)
        let child = TaskNode(title: "Archived child", parentID: parent.id, deviceID: "test")
        child.archivedAt = Date(timeIntervalSinceReferenceDate: 200)
        let independent = TaskNode(title: "Independent archive", parentID: nil, deviceID: "test")
        independent.archivedAt = Date(timeIntervalSinceReferenceDate: 300)
        let deletedArchive = TaskNode(title: "Historical deletion", parentID: nil, deviceID: "test")
        deletedArchive.archivedAt = Date(timeIntervalSinceReferenceDate: 400)
        deletedArchive.deletedAt = Date(timeIntervalSinceReferenceDate: 500)
        let store = makeTestStore()
        store.tasks = [parent, child, independent, deletedArchive]
        store.rebuildTaskIndexes()

        #expect(store.archivedTasks.map(\.id) == [independent.id, child.id, parent.id])
        #expect(store.hasArchivedAncestor(for: parent) == false)
        #expect(store.hasArchivedAncestor(for: child))
        #expect(store.hasArchivedAncestor(for: independent) == false)
    }

    @Test @MainActor
    func archivedSettingsLeavesARecoveryEntryForMalformedHierarchyCycles() throws {
        let selfCycle = TaskNode(title: "Self cycle", parentID: nil, deviceID: "test")
        selfCycle.parentID = selfCycle.id
        selfCycle.archivedAt = Date(timeIntervalSinceReferenceDate: 100)

        let first = TaskNode(title: "First", parentID: nil, deviceID: "test")
        let second = TaskNode(title: "Second", parentID: first.id, deviceID: "test")
        first.parentID = second.id
        first.archivedAt = Date(timeIntervalSinceReferenceDate: 200)
        second.archivedAt = Date(timeIntervalSinceReferenceDate: 300)

        let store = makeTestStore()
        store.tasks = [selfCycle, first, second]
        store.rebuildTaskIndexes()
        let repairPlan = TaskHierarchyRepairPlan(tasks: [first, second])
        let cycleBreakerID = try #require(repairPlan.cycleBreakerTaskIDs.first)
        let cycleBreaker = try #require(store.task(for: cycleBreakerID))
        let blockedCycleTask = try #require(
            [first, second].first { $0.id != cycleBreakerID }
        )

        #expect(store.hasArchivedAncestor(for: selfCycle) == false)
        #expect(store.hasArchivedAncestor(for: cycleBreaker) == false)
        #expect(store.hasArchivedAncestor(for: blockedCycleTask))
    }

    @Test @MainActor
    func archivedSettingsObservesReadModelRevisionWhenVisibleTreeIsUnchanged() {
        let parent = TaskNode(title: "Archived parent", parentID: nil, deviceID: "test")
        parent.archivedAt = Date(timeIntervalSinceReferenceDate: 100)
        let child = TaskNode(title: "Archived child", parentID: parent.id, deviceID: "test")
        child.archivedAt = Date(timeIntervalSinceReferenceDate: 200)
        let store = makeTestStore()
        store.tasks = [parent, child]
        var didInvalidate = false
        withObservationTracking {
            _ = store.archivedTasks.map(\.id)
        } onChange: {
            didInvalidate = true
        }

        store.rebuildTaskIndexes()

        #expect(didInvalidate)
        #expect(store.archivedTasks.map(\.id) == [child.id, parent.id])
    }

    @Test @MainActor
    func repositoryRejectsCreatingOrMovingTasksIntoAnArchivedSubtree() throws {
        let context = try makeTestContext()
        let repository = SwiftDataTaskRepository(context: context, deviceID: "test")
        let archivedRoot = try repository.createTask(
            title: "Archived root",
            parentID: nil,
            colorHex: nil,
            iconName: nil
        )
        let activeRoot = try repository.createTask(
            title: "Active root",
            parentID: nil,
            colorHex: nil,
            iconName: nil
        )
        try repository.archiveTask(taskID: archivedRoot.id)

        #expect(throws: TaskRepositoryError.invalidMove) {
            try repository.createTask(
                title: "Invalid child",
                parentID: archivedRoot.id,
                colorHex: nil,
                iconName: nil
            )
        }
        #expect(throws: TaskRepositoryError.invalidMove) {
            try repository.moveTask(taskID: activeRoot.id, newParentID: archivedRoot.id, sortOrder: 10)
        }
        #expect(throws: TaskRepositoryError.invalidMove) {
            try repository.moveTask(taskID: archivedRoot.id, newParentID: activeRoot.id, sortOrder: 10)
        }
        #expect(try repository.allNodes().map(\.id).contains(activeRoot.id))
    }

    @Test @MainActor
    func repositoryTreatsLegacyCompletedBranchesAsOrdinaryHierarchy() throws {
        let context = try makeTestContext()
        let repository = SwiftDataTaskRepository(context: context, deviceID: "test")
        let completedRoot = try repository.createTask(
            title: "Completed root",
            parentID: nil,
            colorHex: nil,
            iconName: nil
        )
        let child = try repository.createTask(
            title: "Existing child",
            parentID: completedRoot.id,
            colorHex: nil,
            iconName: nil
        )
        let activeRoot = try repository.createTask(
            title: "Active root",
            parentID: nil,
            colorHex: nil,
            iconName: nil
        )
        completedRoot.statusRaw = LegacyTaskStatusRaw.completed
        try context.save()

        let newChild = try repository.createTask(
            title: "New child",
            parentID: completedRoot.id,
            colorHex: nil,
            iconName: nil
        )
        try repository.updateTask(
            taskID: child.id,
            title: "Updated history",
            parentID: completedRoot.id,
            categoryID: nil,
            colorHex: nil,
            iconName: nil,
            notes: "Preserved",
            estimatedSeconds: nil,
            dueAt: nil
        )
        #expect(try repository.task(id: child.id)?.title == "Updated history")

        try repository.updateTask(
            taskID: child.id,
            title: "Recovered child",
            parentID: activeRoot.id,
            categoryID: nil,
            colorHex: nil,
            iconName: nil,
            notes: "Preserved",
            estimatedSeconds: nil,
            dueAt: nil
        )
        #expect(try repository.task(id: child.id)?.parentID == activeRoot.id)

        try repository.moveTask(
            taskID: completedRoot.id,
            newParentID: activeRoot.id,
            sortOrder: 10
        )
        #expect(try repository.task(id: completedRoot.id)?.parentID == activeRoot.id)
        #expect(try repository.task(id: newChild.id)?.parentID == completedRoot.id)
        #expect(
            try repository.task(id: completedRoot.id)?.statusRaw ==
                LegacyTaskStatusRaw.completed
        )
    }

    @Test @MainActor
    func repositoryPreservesAnUnchangedMissingParentDuringMetadataEdits() throws {
        let context = try makeTestContext()
        let repository = SwiftDataTaskRepository(context: context, deviceID: "test")
        let missingParentID = UUID()
        let task = TaskNode(
            title: "Staged child",
            parentID: missingParentID,
            deviceID: "remote"
        )
        context.insert(task)
        try context.save()

        try repository.updateTask(
            taskID: task.id,
            title: "Edited staged child",
            parentID: missingParentID,
            categoryID: nil,
            colorHex: nil,
            iconName: nil,
            notes: "Keep the staged relationship",
            estimatedSeconds: nil,
            dueAt: nil
        )

        let updated = try #require(try repository.task(id: task.id))
        #expect(updated.title == "Edited staged child")
        #expect(updated.parentID == missingParentID)
        #expect(TaskTreeService().canMove(
            taskID: task.id,
            to: missingParentID,
            tasks: [task]
        ))
    }

    @Test @MainActor
    func taskScopedRefreshRemovesMissingTaskSubtreeAndKeepsUnchangedRows() throws {
        let parent = TaskNode(title: "Deleted parent", parentID: nil, deviceID: "test", sortOrder: 10)
        let child = TaskNode(title: "Deleted child", parentID: parent.id, deviceID: "test", sortOrder: 10)
        let sibling = TaskNode(title: "Keep", parentID: nil, deviceID: "test", sortOrder: 20)

        let repository = TaskStoreTestRepository(tasks: [parent, child, sibling])
        var store = TaskStore()
        try store.refresh(repository: repository)

        repository.tasksByID = [sibling.id: sibling]
        try store.refreshTaskScoped(taskIDs: [parent.id], repository: repository)

        #expect(store.tasks.map(\.id) == [sibling.id])
    }

    @Test @MainActor
    func taskScopedRefreshReplacesFetchedTasksWithoutDroppingUnchangedRows() throws {
        let root = TaskNode(title: "Old", parentID: nil, deviceID: "test", sortOrder: 10)
        let sibling = TaskNode(title: "Keep", parentID: nil, deviceID: "test", sortOrder: 20)

        let repository = TaskStoreTestRepository(tasks: [root, sibling])
        var store = TaskStore()
        try store.refresh(repository: repository)

        let updated = TaskNode(title: "Updated", parentID: nil, deviceID: "test", sortOrder: 10)
        updated.id = root.id
        repository.tasksByID[root.id] = updated

        try store.refreshTaskScoped(taskIDs: [root.id], repository: repository)

        #expect(store.tasks.first { $0.id == root.id }?.title == "Updated")
        #expect(store.tasks.first { $0.id == sibling.id }?.title == "Keep")
    }

    @Test @MainActor
    func taskScopedRefreshUsesUUIDAsTheFinalStableOrder() throws {
        let earlierID = try #require(UUID(uuidString: "00000000-0000-0000-0000-000000000001"))
        let laterID = try #require(UUID(uuidString: "00000000-0000-0000-0000-000000000002"))
        let sharedCreatedAt = Date(timeIntervalSinceReferenceDate: 100)
        let earlier = TaskNode(title: "Same", parentID: nil, deviceID: "test", sortOrder: 10)
        earlier.id = earlierID
        earlier.createdAt = sharedCreatedAt
        let later = TaskNode(title: "Same", parentID: nil, deviceID: "test", sortOrder: 10)
        later.id = laterID
        later.createdAt = sharedCreatedAt

        let repository = TaskStoreTestRepository(tasks: [later, earlier])
        var store = TaskStore()
        try store.refresh(repository: repository)

        try store.refreshTaskScoped(taskIDs: [earlierID, laterID], repository: repository)

        #expect(store.tasks.map(\.id) == [earlierID, laterID])
    }
}

@MainActor
private final class TaskStoreTestRepository: TaskRepository {
    var tasksByID: [UUID: TaskNode]

    init(tasks: [TaskNode]) {
        tasksByID = Dictionary(uniqueKeysWithValues: tasks.map { ($0.id, $0) })
    }

    func allNodes() throws -> [TaskNode] {
        tasksByID.values.sorted { $0.sortOrder < $1.sortOrder }
    }

    func rootNodes() throws -> [TaskNode] {
        try children(of: nil)
    }

    func children(of parentID: UUID?) throws -> [TaskNode] {
        try allNodes().filter { $0.parentID == parentID }
    }

    func task(id: UUID) throws -> TaskNode? {
        tasksByID[id]
    }

    func tasks(ids: Set<UUID>) throws -> [TaskNode] {
        ids.compactMap { tasksByID[$0] }
    }

    func categories() throws -> [TaskCategory] { [] }
    func categoryAssignments() throws -> [TaskCategoryAssignment] { [] }
    func category(id: UUID) throws -> TaskCategory? { nil }
    func categoryID(forRootTaskID taskID: UUID) throws -> UUID? { nil }

    func createCategory(title: String, colorHex: String?, iconName: String?, includesInForecast: Bool) throws -> TaskCategory {
        TaskCategory(title: title, deviceID: "test", colorHex: colorHex, iconName: iconName, includesInForecast: includesInForecast)
    }

    func updateCategory(categoryID: UUID, title: String, colorHex: String?, iconName: String?, includesInForecast: Bool) throws {}
    func softDeleteCategory(categoryID: UUID) throws {}

    func createTask(title: String, parentID: UUID?, categoryID: UUID?, colorHex: String?, iconName: String?) throws -> TaskNode {
        let task = TaskNode(title: title, parentID: parentID, deviceID: "test", colorHex: colorHex, iconName: iconName)
        tasksByID[task.id] = task
        return task
    }

    func updateTask(taskID: UUID, title: String, parentID: UUID?, categoryID: UUID?, colorHex: String?, iconName: String?, notes: String?, estimatedSeconds: Int?, dueAt: Date?) throws {}
    func moveTask(taskID: UUID, newParentID: UUID?, sortOrder: Double) throws {}
    func archiveTask(taskID: UUID) throws {}
    func unarchiveTask(taskID: UUID) throws {}
}
