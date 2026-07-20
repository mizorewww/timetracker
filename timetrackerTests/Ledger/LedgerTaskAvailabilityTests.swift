import Foundation
import SwiftData
import Testing
@testable import timetracker

@Suite(.serialized)
struct LedgerTaskAvailabilityTests {
    @Test @MainActor
    func newTrackingRejectsUnavailableAndHealthSyncBranchesWithoutCreatingLedgerRows() throws {
        let context = try makeTestContext()
        let now = Date(timeIntervalSinceReferenceDate: 1_000_000)
        let taskRepository = SwiftDataTaskRepository(context: context, deviceID: "task-device")
        let deletedTask = try taskRepository.createTask(
            title: "Deleted task",
            parentID: nil,
            colorHex: nil,
            iconName: nil
        )
        let archivedParent = try taskRepository.createTask(
            title: "Archived parent",
            parentID: nil,
            colorHex: nil,
            iconName: nil
        )
        let archivedChild = try taskRepository.createTask(
            title: "Child of archived parent",
            parentID: archivedParent.id,
            colorHex: nil,
            iconName: nil
        )
        let healthRoot = TaskNode(
            title: "Imported running",
            parentID: nil,
            deviceID: "health"
        )
        healthRoot.id = AppleHealthTaskCatalog.taskDefinition(
            for: .workout(.running)
        ).id
        let healthChild = TaskNode(
            title: "Imported child",
            parentID: healthRoot.id,
            deviceID: "health"
        )
        context.insert(healthRoot)
        context.insert(healthChild)

        let tombstonedAt = deletedTask.updatedAt.addingTimeInterval(1)
        deletedTask.deletedAt = tombstonedAt
        deletedTask.updatedAt = tombstonedAt
        deletedTask.deviceID = "legacy-sync"
        deletedTask.clientMutationID = UUID()
        try context.save()
        try taskRepository.archiveTask(taskID: archivedParent.id)

        let repository = SwiftDataTimeTrackingRepository(
            context: context,
            deviceID: "ledger-device",
            nowProvider: { now }
        )
        let unavailableTaskIDs = [
            UUID(),
            deletedTask.id,
            archivedParent.id,
            archivedChild.id,
            healthRoot.id,
            healthChild.id,
        ]

        for taskID in unavailableTaskIDs {
            #expect(throws: TimeTrackingRepositoryError.taskUnavailable) {
                try repository.startTask(taskID: taskID, source: .timer)
            }
            #expect(throws: TimeTrackingRepositoryError.taskUnavailable) {
                try repository.addManualSegment(
                    taskID: taskID,
                    startedAt: now.addingTimeInterval(-120),
                    endedAt: now.addingTimeInterval(-60),
                    note: "Must not persist"
                )
            }
        }

        #expect(try repository.sessions().isEmpty)
        #expect(try repository.allSegments().isEmpty)
    }

    @Test @MainActor
    func legacyPlannedAndCompletedTasksStillAcceptTimerAndManualTracking() throws {
        let context = try makeTestContext()
        let now = Date(timeIntervalSinceReferenceDate: 2_000_000)
        let taskRepository = SwiftDataTaskRepository(
            context: context,
            deviceID: "task-device"
        )
        let plannedTask = try taskRepository.createTask(
            title: "Legacy planned",
            parentID: nil,
            colorHex: nil,
            iconName: nil
        )
        let completedTask = try taskRepository.createTask(
            title: "Legacy completed",
            parentID: nil,
            colorHex: nil,
            iconName: nil
        )
        let completedParent = try taskRepository.createTask(
            title: "Legacy completed parent",
            parentID: nil,
            colorHex: nil,
            iconName: nil
        )
        let completedChild = try taskRepository.createTask(
            title: "Child of legacy completed parent",
            parentID: completedParent.id,
            colorHex: nil,
            iconName: nil
        )
        plannedTask.statusRaw = LegacyTaskStatusRaw.planned
        completedTask.statusRaw = LegacyTaskStatusRaw.completed
        completedParent.statusRaw = LegacyTaskStatusRaw.completed
        try context.save()

        let repository = SwiftDataTimeTrackingRepository(
            context: context,
            deviceID: "ledger-device",
            nowProvider: { now }
        )
        let legacyTasks = [
            plannedTask,
            completedTask,
            completedParent,
            completedChild,
        ]

        for task in legacyTasks {
            _ = try repository.startTask(taskID: task.id, source: .timer)
            _ = try repository.addManualSegment(
                taskID: task.id,
                startedAt: now.addingTimeInterval(-120),
                endedAt: now.addingTimeInterval(-60),
                note: "Legacy raw value must stay inert"
            )
        }

        let sessions = try repository.sessions()
        #expect(sessions.count == legacyTasks.count * 2)
        #expect(Set(sessions.map(\.taskID)) == Set(legacyTasks.map(\.id)))
        #expect(try repository.allSegments().count == legacyTasks.count * 2)
    }

    @Test @MainActor
    func rebindAcceptsLegacyCompletedTargetButRejectsArchivedBranch() throws {
        let context = try makeTestContext()
        let now = Date(timeIntervalSinceReferenceDate: 3_000_000)
        let taskRepository = SwiftDataTaskRepository(context: context, deviceID: "task-device")
        let sourceTask = try taskRepository.createTask(
            title: "Source task",
            parentID: nil,
            colorHex: nil,
            iconName: nil
        )
        let completedTarget = try taskRepository.createTask(
            title: "Completed target",
            parentID: nil,
            colorHex: nil,
            iconName: nil
        )
        let archivedParent = try taskRepository.createTask(
            title: "Archived parent",
            parentID: nil,
            colorHex: nil,
            iconName: nil
        )
        let blockedTarget = try taskRepository.createTask(
            title: "Blocked target",
            parentID: archivedParent.id,
            colorHex: nil,
            iconName: nil
        )
        let start = now.addingTimeInterval(-600)
        let repository = SwiftDataTimeTrackingRepository(
            context: context,
            deviceID: "ledger-device",
            nowProvider: { now }
        )
        let segment = try repository.addManualSegment(
            taskID: sourceTask.id,
            startedAt: start,
            endedAt: start.addingTimeInterval(300),
            note: "Original note"
        )
        let session = try #require(try repository.sessions().first { $0.id == segment.sessionID })
        completedTarget.statusRaw = LegacyTaskStatusRaw.completed
        try context.save()
        try taskRepository.archiveTask(taskID: archivedParent.id)

        let acceptedStart = start.addingTimeInterval(60)
        let acceptedEnd = start.addingTimeInterval(420)
        try repository.updateSegment(
            segmentID: segment.id,
            taskID: completedTarget.id,
            startedAt: acceptedStart,
            endedAt: acceptedEnd,
            note: "Legacy completed remains usable"
        )
        #expect(segment.taskID == completedTarget.id)
        #expect(session.taskID == completedTarget.id)
        #expect(session.titleSnapshot == completedTarget.title)

        let acceptedSegmentUpdatedAt = segment.updatedAt
        let acceptedSessionUpdatedAt = session.updatedAt
        let acceptedMutationID = session.clientMutationID

        #expect(throws: TimeTrackingRepositoryError.taskUnavailable) {
            try repository.updateSegment(
                segmentID: segment.id,
                taskID: blockedTarget.id,
                startedAt: start.addingTimeInterval(120),
                endedAt: start.addingTimeInterval(480),
                note: "Must not persist"
            )
        }

        #expect(segment.taskID == completedTarget.id)
        #expect(segment.startedAt == acceptedStart)
        #expect(segment.endedAt == acceptedEnd)
        #expect(segment.updatedAt == acceptedSegmentUpdatedAt)
        #expect(session.taskID == completedTarget.id)
        #expect(session.titleSnapshot == completedTarget.title)
        #expect(session.note == "Legacy completed remains usable")
        #expect(session.updatedAt == acceptedSessionUpdatedAt)
        #expect(session.clientMutationID == acceptedMutationID)
    }
}
