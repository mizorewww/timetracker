import Foundation
import SwiftData
import Testing
@testable import timetracker

@Suite(.serialized)
struct CoreCommandHandlerTests {
    @Test @MainActor
    func checklistCommandHandlerOwnsAddAndToggleSemantics() throws {
        let context = try makeTestContext()
        let task = TaskNode(title: "Command Task", parentID: nil, deviceID: "test")
        context.insert(task)
        try context.save()

        let handler = ChecklistCommandHandler()
        let firstResult = try handler.add(taskID: task.id, title: " First ", existingItems: [], context: context, deviceID: "test")
        let first = try #require(firstResult)
        let secondResult = try handler.add(taskID: task.id, title: "Second", existingItems: [first], context: context, deviceID: "test")
        let second = try #require(secondResult)
        let blank = try handler.add(taskID: task.id, title: "   ", existingItems: [first, second], context: context, deviceID: "test")

        #expect(blank == nil)
        #expect(first.title == "First")
        #expect(second.sortOrder > first.sortOrder)

        try handler.toggle(first, context: context, now: Date(timeIntervalSince1970: 1_000))
        #expect(first.isCompleted)
        #expect(first.completedAt == Date(timeIntervalSince1970: 1_000))

        try handler.toggle(first, context: context, now: Date(timeIntervalSince1970: 2_000))
        #expect(first.isCompleted == false)
        #expect(first.completedAt == nil)
    }

    @Test @MainActor
    func timerCommandHandlerCoordinatesLedgerAndParallelTimerPolicy() throws {
        let context = try makeTestContext()
        let repository = SwiftDataTimeTrackingRepository(context: context, deviceID: "test")
        let firstTaskID = UUID()
        let secondTaskID = UUID()
        let firstSegment = try repository.startTask(taskID: firstTaskID, source: .timer)

        try TimerCommandHandler().startTask(
            taskID: secondTaskID,
            allowParallelTimers: false,
            activeSegments: [firstSegment],
            pausedSessions: [],
            pomodoroRuns: [],
            timeRepository: repository,
            context: context
        )

        let activeSegments = try repository.activeSegments()
        #expect(firstSegment.endedAt != nil)
        #expect(activeSegments.count == 1)
        #expect(activeSegments.first?.taskID == secondTaskID)
    }

    @Test @MainActor
    func pomodoroCommandHandlerOwnsTimerStateTransitions() throws {
        let context = try makeTestContext()
        let sessionID = UUID()
        let run = PomodoroRun(taskID: UUID(), deviceID: "test")
        run.sessionID = sessionID
        run.state = .focusing
        context.insert(run)
        try context.save()

        let handler = PomodoroCommandHandler()
        let interruptedAt = Date(timeIntervalSince1970: 1_000)
        try handler.interruptIfNeeded(sessionID: sessionID, runs: [run], context: context, now: interruptedAt)
        #expect(run.state == .interrupted)
        #expect(run.updatedAt == interruptedAt)

        let resumedAt = Date(timeIntervalSince1970: 2_000)
        try handler.resumeIfNeeded(sessionID: sessionID, runs: [run], context: context, now: resumedAt)
        #expect(run.state == .focusing)
        #expect(run.updatedAt == resumedAt)

        let cancelledAt = Date(timeIntervalSince1970: 3_000)
        try handler.cancelIfNeeded(sessionID: sessionID, runs: [run], context: context, now: cancelledAt)
        #expect(run.state == .cancelled)
        #expect(run.endedAt == cancelledAt)
    }

    @Test @MainActor
    func ledgerCommandHandlerOwnsManualSegmentWrites() throws {
        let context = try makeTestContext()
        let repository = SwiftDataTimeTrackingRepository(context: context, deviceID: "test")
        let task = TaskNode(title: "Ledger Task", parentID: nil, deviceID: "test")
        var draft = ManualTimeDraft(taskID: task.id, tasks: [task])
        draft.startedAt = Date(timeIntervalSince1970: 10_000)
        draft.endedAt = draft.startedAt.addingTimeInterval(1_200)
        draft.note = "   "

        let segment = try LedgerCommandHandler().addManualTime(draft: draft, taskID: task.id, repository: repository)
        let session = try #require(try repository.sessions().first { $0.id == segment.sessionID })

        #expect(segment.taskID == task.id)
        #expect(session.note == "Manual")

        var editDraft = SegmentEditorDraft(segment: segment, note: " Updated ")
        editDraft.isActive = true
        try LedgerCommandHandler().updateSegment(draft: editDraft, taskID: task.id, repository: repository)
        #expect(segment.endedAt == nil)
        #expect(session.note == "Updated")

        try LedgerCommandHandler().softDeleteSegment(segment.id, repository: repository)
        #expect(segment.deletedAt != nil)
    }

    @Test @MainActor
    func countdownCommandHandlerOwnsCountdownWrites() throws {
        let context = try makeTestContext()
        let handler = CountdownCommandHandler()
        let event = try handler.add(context: context, deviceID: "test")
        let date = Date(timeIntervalSince1970: 50_000)

        try handler.update(event, title: "Ship", date: date, context: context, now: Date(timeIntervalSince1970: 40_000))
        #expect(event.title == "Ship")
        #expect(event.date == date)
        #expect(event.updatedAt == Date(timeIntervalSince1970: 40_000))

        try handler.softDelete(event, context: context, now: Date(timeIntervalSince1970: 60_000))
        #expect(event.deletedAt == Date(timeIntervalSince1970: 60_000))
    }

    @Test @MainActor
    func csvExportServiceEscapesRowsAndUsesSessionFallbackForDeletedTasks() {
        let taskID = UUID()
        let session = TimeSession(
            taskID: taskID,
            source: .manual,
            deviceID: "test",
            startedAt: Date(timeIntervalSince1970: 30_000),
            titleSnapshot: "Deleted, Task"
        )
        session.endedAt = session.startedAt.addingTimeInterval(120)
        session.note = "Said \"hello\""
        let segment = TimeSegment(
            sessionID: session.id,
            taskID: taskID,
            source: .manual,
            deviceID: "test",
            startedAt: session.startedAt,
            endedAt: session.endedAt
        )

        let csv = CSVExportService().export(
            segments: [segment],
            sessions: [session],
            taskByID: [:],
            taskParentPathByID: [:],
            now: session.endedAt ?? session.startedAt
        )

        #expect(csv.contains("\"Deleted, Task\""))
        #expect(csv.contains(AppStrings.localized("task.deleted.path")))
        #expect(csv.contains("\"Said \"\"hello\"\"\""))
    }
}
