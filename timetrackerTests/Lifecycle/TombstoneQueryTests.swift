import Foundation
import SwiftData
import Testing
@testable import timetracker

@Suite(.serialized)
struct TombstoneQueryTests {
    @Test @MainActor
    func repositoriesResolveLastWriteWinsBeforeFilteringTombstones() throws {
        let context = try makeTestContext()
        let base = Date(timeIntervalSinceReferenceDate: 900_000)
        let taskID = UUID()

        let activeTask = TaskNode(title: "Old active task", parentID: nil, deviceID: "old")
        activeTask.id = taskID
        activeTask.createdAt = base
        activeTask.updatedAt = base
        let deletedTask = TaskNode(title: "Deleted task", parentID: nil, deviceID: "new")
        deletedTask.id = taskID
        deletedTask.createdAt = base
        deletedTask.updatedAt = base.addingTimeInterval(10)
        deletedTask.deletedAt = deletedTask.updatedAt

        let session = TimeSession(taskID: taskID, source: .timer, deviceID: "test", startedAt: base)
        let segmentID = UUID()
        let activeSegment = TimeSegment(
            sessionID: session.id,
            taskID: taskID,
            source: .timer,
            deviceID: "old",
            startedAt: base.addingTimeInterval(60)
        )
        activeSegment.id = segmentID
        activeSegment.createdAt = base
        activeSegment.updatedAt = base
        let deletedSegment = TimeSegment(
            sessionID: session.id,
            taskID: taskID,
            source: .timer,
            deviceID: "new",
            startedAt: base.addingTimeInterval(10_000),
            endedAt: base.addingTimeInterval(10_060)
        )
        deletedSegment.id = segmentID
        deletedSegment.createdAt = base
        deletedSegment.updatedAt = base.addingTimeInterval(10)
        deletedSegment.deletedAt = deletedSegment.updatedAt

        let runID = UUID()
        let activeRun = PomodoroRun(taskID: taskID, deviceID: "old")
        activeRun.id = runID
        activeRun.state = .focusing
        activeRun.startedAt = base
        activeRun.createdAt = base
        activeRun.updatedAt = base
        let deletedRun = PomodoroRun(taskID: taskID, deviceID: "new")
        deletedRun.id = runID
        deletedRun.state = .cancelled
        deletedRun.endedAt = base.addingTimeInterval(100)
        deletedRun.createdAt = base
        deletedRun.updatedAt = base.addingTimeInterval(10)
        deletedRun.deletedAt = deletedRun.updatedAt

        let checklistID = UUID()
        let activeChecklist = ChecklistItem(taskID: taskID, title: "Old checklist", deviceID: "old")
        activeChecklist.id = checklistID
        activeChecklist.createdAt = base
        activeChecklist.updatedAt = base
        let deletedChecklist = ChecklistItem(taskID: taskID, title: "Deleted checklist", deviceID: "new")
        deletedChecklist.id = checklistID
        deletedChecklist.createdAt = base
        deletedChecklist.updatedAt = base.addingTimeInterval(10)
        deletedChecklist.deletedAt = deletedChecklist.updatedAt

        let inboxID = UUID()
        let activeInbox = InboxItem(title: "Old inbox", deviceID: "old")
        activeInbox.id = inboxID
        activeInbox.createdAt = base
        activeInbox.updatedAt = base
        let deletedInbox = InboxItem(title: "Deleted inbox", deviceID: "new")
        deletedInbox.id = inboxID
        deletedInbox.createdAt = base
        deletedInbox.updatedAt = base.addingTimeInterval(10)
        deletedInbox.deletedAt = deletedInbox.updatedAt

        [activeTask, deletedTask].forEach(context.insert)
        context.insert(session)
        [activeSegment, deletedSegment].forEach(context.insert)
        [activeRun, deletedRun].forEach(context.insert)
        [activeChecklist, deletedChecklist].forEach(context.insert)
        [activeInbox, deletedInbox].forEach(context.insert)
        try context.save()

        let taskRepository = SwiftDataTaskRepository(context: context, deviceID: "test")
        #expect(try taskRepository.allNodes().isEmpty)
        #expect(try taskRepository.task(id: taskID) == nil)

        let timeRepository = SwiftDataTimeTrackingRepository(context: context, deviceID: "test")
        #expect(try timeRepository.activeSegments().isEmpty)
        #expect(try timeRepository.allSegments().isEmpty)
        #expect(try timeRepository.segments(
            from: base,
            to: base.addingTimeInterval(3_600),
            now: base.addingTimeInterval(1_800)
        ).isEmpty)

        let pomodoroRepository = SwiftDataPomodoroRepository(
            context: context,
            timeRepository: timeRepository,
            deviceID: "test"
        )
        #expect(try pomodoroRepository.runs().isEmpty)
        #expect(try pomodoroRepository.activeRuns().isEmpty)

        let store = makeTestStore()
        store.modelContext = context
        #expect(try store.fetchChecklistItems().isEmpty)
        #expect(try store.fetchInboxItems().isEmpty)
    }
}
