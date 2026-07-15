import Foundation
import SwiftData
import Testing
@testable import timetracker

@Suite(.serialized)
struct LedgerTaskAvailabilityTests {
    @Test @MainActor
    func newTrackingRejectsUnavailableTasksWithoutCreatingLedgerRows() throws {
        let context = try makeTestContext()
        let now = Date(timeIntervalSinceReferenceDate: 1_000_000)
        let taskRepository = SwiftDataTaskRepository(context: context, deviceID: "task-device")
        let completedTask = try taskRepository.createTask(
            title: "Completed task",
            parentID: nil,
            colorHex: nil,
            iconName: nil
        )
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
        let completedParent = try taskRepository.createTask(
            title: "Completed parent",
            parentID: nil,
            colorHex: nil,
            iconName: nil
        )
        let completedChild = try taskRepository.createTask(
            title: "Child of completed parent",
            parentID: completedParent.id,
            colorHex: nil,
            iconName: nil
        )

        try taskRepository.setTaskStatus(taskID: completedTask.id, status: .completed)
        try taskRepository.softDeleteTask(taskID: deletedTask.id)
        try taskRepository.archiveTask(taskID: archivedParent.id)
        try taskRepository.setTaskStatus(taskID: completedParent.id, status: .completed)

        let repository = SwiftDataTimeTrackingRepository(
            context: context,
            deviceID: "ledger-device",
            nowProvider: { now }
        )
        let unavailableTaskIDs = [
            UUID(),
            deletedTask.id,
            completedTask.id,
            archivedChild.id,
            completedChild.id,
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
    func activeTaskStillAcceptsTimerAndManualTracking() throws {
        let context = try makeTestContext()
        let now = Date(timeIntervalSinceReferenceDate: 2_000_000)
        let task = try SwiftDataTaskRepository(context: context, deviceID: "task-device").createTask(
            title: "Trackable task",
            parentID: nil,
            colorHex: nil,
            iconName: nil
        )
        let repository = SwiftDataTimeTrackingRepository(
            context: context,
            deviceID: "ledger-device",
            nowProvider: { now }
        )

        _ = try repository.startTask(taskID: task.id, source: .timer)
        _ = try repository.addManualSegment(
            taskID: task.id,
            startedAt: now.addingTimeInterval(-120),
            endedAt: now.addingTimeInterval(-60),
            note: "Valid note"
        )

        let sessions = try repository.sessions()
        #expect(sessions.count == 2)
        #expect(sessions.allSatisfy { $0.taskID == task.id && $0.titleSnapshot == task.title })
        #expect(try repository.allSegments().count == 2)
    }

    @Test @MainActor
    func rebindRejectsCompletedOrBlockedTargetsWithoutChangingHistory() throws {
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
        let originalSegmentUpdatedAt = segment.updatedAt
        let originalSessionUpdatedAt = session.updatedAt
        let originalMutationID = session.clientMutationID

        try taskRepository.setTaskStatus(taskID: completedTarget.id, status: .completed)
        try taskRepository.archiveTask(taskID: archivedParent.id)

        for targetID in [completedTarget.id, blockedTarget.id] {
            #expect(throws: TimeTrackingRepositoryError.taskUnavailable) {
                try repository.updateSegment(
                    segmentID: segment.id,
                    taskID: targetID,
                    startedAt: start.addingTimeInterval(60),
                    endedAt: start.addingTimeInterval(420),
                    note: "Must not persist"
                )
            }

            #expect(segment.taskID == sourceTask.id)
            #expect(segment.startedAt == start)
            #expect(segment.endedAt == start.addingTimeInterval(300))
            #expect(segment.updatedAt == originalSegmentUpdatedAt)
            #expect(session.taskID == sourceTask.id)
            #expect(session.titleSnapshot == sourceTask.title)
            #expect(session.note == "Original note")
            #expect(session.updatedAt == originalSessionUpdatedAt)
            #expect(session.clientMutationID == originalMutationID)
        }
    }
}
