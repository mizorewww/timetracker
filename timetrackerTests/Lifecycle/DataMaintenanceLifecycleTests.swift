import Foundation
import SwiftData
import Testing
@testable import timetracker

@Suite(.serialized)
struct DataMaintenanceLifecycleTests {
    @Test @MainActor
    func optimizeDatabaseRemovesLedgerRowsForSoftDeletedTasks() throws {
        let context = try makeTestContext()
        let taskRepository = SwiftDataTaskRepository(context: context, deviceID: "test")
        let timeRepository = SwiftDataTimeTrackingRepository(context: context, deviceID: "test")
        let task = try taskRepository.createTask(title: "Temporary Client", parentID: nil, colorHex: nil, iconName: nil)
        let start = Date().addingTimeInterval(-1_800)
        let session = try timeRepository.addManualSegment(
            taskID: task.id,
            startedAt: start,
            endedAt: start.addingTimeInterval(900),
            note: nil
        )
        let run = PomodoroRun(taskID: task.id, deviceID: "test")
        run.sessionID = session.id
        run.state = .completed
        context.insert(run)
        try context.save()
        try taskRepository.softDeleteTask(taskID: task.id)

        let store = TimeTrackerStore()
        store.configureIfNeeded(context: context)
        #expect(store.allSegments.count == 1)

        let removedCount = store.optimizeDatabase()

        #expect(removedCount == 3)
        #expect(try timeRepository.allSegments().isEmpty)
        #expect(try timeRepository.sessions().isEmpty)
        #expect(try context.fetch(FetchDescriptor<PomodoroRun>()).isEmpty)
        #expect(try context.fetch(FetchDescriptor<TaskNode>()).contains { $0.id == task.id && $0.deletedAt != nil })
    }

    @Test @MainActor
    func optimizeDatabaseRemovesOnlyTrulyOrphanedLedgerRows() throws {
        let context = try makeTestContext()
        let missingTaskID = UUID()
        let session = TimeSession(taskID: missingTaskID, source: .manual, deviceID: "test")
        session.endedAt = Date()
        let segment = TimeSegment(
            sessionID: session.id,
            taskID: missingTaskID,
            source: .manual,
            deviceID: "test",
            startedAt: Date().addingTimeInterval(-900),
            endedAt: Date()
        )
        context.insert(session)
        context.insert(segment)
        try context.save()

        let store = TimeTrackerStore()
        store.configureIfNeeded(context: context)

        let removedCount = store.optimizeDatabase()

        #expect(removedCount == 2)
        #expect(try context.fetch(FetchDescriptor<TimeSegment>()).contains { $0.id == segment.id } == false)
        #expect(try context.fetch(FetchDescriptor<TimeSession>()).contains { $0.id == session.id } == false)
    }
}
