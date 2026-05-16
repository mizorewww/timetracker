import Foundation
import SwiftData
import Testing
@testable import timetracker

@Suite(.serialized)
struct DataMaintenanceLifecycleTests {
    @Test @MainActor
    func resetDataDeletesAllPersistentModels() throws {
        let context = try makeTestContext()
        let task = TaskNode(title: "Reset me", parentID: nil, deviceID: "test")
        let category = TaskCategory(title: "Reset category", deviceID: "test")
        let assignment = TaskCategoryAssignment(taskID: task.id, categoryID: category.id, deviceID: "test")
        let session = TimeSession(taskID: task.id, source: .manual, deviceID: "test")
        session.endedAt = Date()
        let segment = TimeSegment(
            sessionID: session.id,
            taskID: task.id,
            source: .manual,
            deviceID: "test",
            startedAt: Date().addingTimeInterval(-900),
            endedAt: Date()
        )
        let pomodoro = PomodoroRun(taskID: task.id, deviceID: "test")
        let summary = DailySummary(date: Date(), taskID: task.id, grossSeconds: 900, wallClockSeconds: 900, pomodoroCount: 1, interruptionCount: 0)
        let countdown = CountdownEvent(title: "Reset countdown", date: Date(), deviceID: "test")
        let preference = SyncedPreference(key: AppPreferenceKey.showGrossAndWallTogether.rawValue, valueJSON: "true", deviceID: "test")
        let checklistItem = ChecklistItem(taskID: task.id, title: "Reset checklist", deviceID: "test")
        let checklistVisual = ChecklistItemVisual(checklistItemID: checklistItem.id, deviceID: "test")
        let inboxItem = InboxItem(title: "Reset inbox", deviceID: "test")
        let inboxSuggestion = InboxSuggestion(inboxItemID: inboxItem.id, taskID: task.id, titleSnapshot: inboxItem.title, deviceID: "test")

        context.insert(task)
        context.insert(category)
        context.insert(assignment)
        context.insert(session)
        context.insert(segment)
        context.insert(pomodoro)
        context.insert(summary)
        context.insert(countdown)
        context.insert(preference)
        context.insert(checklistItem)
        context.insert(checklistVisual)
        context.insert(inboxItem)
        context.insert(inboxSuggestion)
        try context.save()

        let store = TimeTrackerStore()
        store.configureIfNeeded(context: context)
        store.selectedTaskID = task.id
        store.desktopTaskDetailID = task.id

        store.clearAllData()

        #expect(store.errorMessage == nil)
        #expect(store.tasks.isEmpty)
        #expect(store.allSegments.isEmpty)
        #expect(store.pomodoroRuns.isEmpty)
        #expect(store.countdownEvents.isEmpty)
        #expect(store.syncedPreferences.isEmpty)
        #expect(store.selectedTaskID == nil)
        #expect(store.desktopTaskDetailID == nil)
        #expect(try context.fetch(FetchDescriptor<TaskNode>()).isEmpty)
        #expect(try context.fetch(FetchDescriptor<TaskCategory>()).isEmpty)
        #expect(try context.fetch(FetchDescriptor<TaskCategoryAssignment>()).isEmpty)
        #expect(try context.fetch(FetchDescriptor<TimeSession>()).isEmpty)
        #expect(try context.fetch(FetchDescriptor<TimeSegment>()).isEmpty)
        #expect(try context.fetch(FetchDescriptor<PomodoroRun>()).isEmpty)
        #expect(try context.fetch(FetchDescriptor<DailySummary>()).isEmpty)
        #expect(try context.fetch(FetchDescriptor<CountdownEvent>()).isEmpty)
        #expect(try context.fetch(FetchDescriptor<SyncedPreference>()).isEmpty)
        #expect(try context.fetch(FetchDescriptor<ChecklistItem>()).isEmpty)
        #expect(try context.fetch(FetchDescriptor<ChecklistItemVisual>()).isEmpty)
        #expect(try context.fetch(FetchDescriptor<InboxItem>()).isEmpty)
        #expect(try context.fetch(FetchDescriptor<InboxSuggestion>()).isEmpty)
    }

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
