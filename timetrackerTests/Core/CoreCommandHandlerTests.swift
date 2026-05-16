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
    func checklistDraftServicePreservesUnrelatedVisualsWhenSavingOneTask() throws {
        let context = try makeTestContext()
        let targetTaskID = UUID()
        let otherItem = ChecklistItem(taskID: UUID(), title: "Other", deviceID: "test")
        let otherVisual = ChecklistItemVisual(
            checklistItemID: otherItem.id,
            iconName: "book",
            colorHex: "16A34A",
            deviceID: "test"
        )
        context.insert(otherItem)
        context.insert(otherVisual)
        try context.save()

        try ChecklistDraftService().save(
            drafts: [
                ChecklistEditorDraft(
                    title: "Target",
                    isCompleted: false,
                    iconName: "paintbrush",
                    colorHex: "1677FF"
                )
            ],
            taskID: targetTaskID,
            context: context,
            deviceID: "test"
        )

        #expect(otherVisual.deletedAt == nil)
        #expect(otherVisual.iconName == "book")
        #expect(otherVisual.colorHex == "16A34A")
    }

    @Test @MainActor
    func inboxCommandHandlerCapturesLooseItemsAndInvalidatesSuggestionsOnEdit() throws {
        let context = try makeTestContext()
        let handler = InboxCommandHandler()

        let firstResult = try handler.add(title: "  Buy notebook  ", existingItems: [], context: context, deviceID: "test")
        let first = try #require(firstResult)
        let blank = try handler.add(title: "   ", existingItems: [first], context: context, deviceID: "test")

        #expect(blank == nil)
        #expect(first.title == "Buy notebook")
        #expect(first.suggestedTaskID == nil)

        let suggestedTaskID = UUID()
        first.suggestedTaskID = suggestedTaskID
        first.suggestionReason = "Likely writing task"
        first.suggestionGeneratedAt = Date(timeIntervalSince1970: 900)
        let suggestion = InboxSuggestion(
            inboxItemID: first.id,
            taskID: suggestedTaskID,
            reason: "Likely writing task",
            iconName: "book",
            colorHex: "16A34A",
            titleSnapshot: first.title,
            deviceID: "test"
        )
        context.insert(suggestion)
        try context.save()

        try handler.updateTitle(first, title: "Buy ink", context: context, now: Date(timeIntervalSince1970: 1_000))
        #expect(first.title == "Buy ink")
        #expect(first.suggestedTaskID == nil)
        #expect(first.suggestionReason == nil)
        #expect(first.suggestionGeneratedAt == nil)
        #expect(suggestion.deletedAt == Date(timeIntervalSince1970: 1_000))

        let refreshedSuggestion = InboxSuggestion(
            inboxItemID: first.id,
            taskID: suggestedTaskID,
            reason: "Likely writing task",
            iconName: "book",
            colorHex: "16A34A",
            titleSnapshot: first.title,
            deviceID: "test"
        )
        context.insert(refreshedSuggestion)
        first.suggestedTaskID = suggestedTaskID
        first.suggestionReason = "Likely writing task"
        first.suggestionGeneratedAt = Date(timeIntervalSince1970: 1_500)
        try context.save()

        try handler.discardSuggestion(first, context: context, now: Date(timeIntervalSince1970: 1_600))
        #expect(first.suggestedTaskID == nil)
        #expect(first.suggestionReason == nil)
        #expect(first.suggestionGeneratedAt == Date(timeIntervalSince1970: 1_600))
        #expect(refreshedSuggestion.deletedAt == Date(timeIntervalSince1970: 1_600))

        try handler.toggle(first, context: context, now: Date(timeIntervalSince1970: 2_000))
        #expect(first.isCompleted)
        #expect(first.completedAt == Date(timeIntervalSince1970: 2_000))

        try handler.softDelete(first, context: context, now: Date(timeIntervalSince1970: 3_000))
        #expect(first.deletedAt == Date(timeIntervalSince1970: 3_000))
    }

    @Test @MainActor
    func inboxCommandHandlerReordersOnlyOpenItems() throws {
        let context = try makeTestContext()
        let handler = InboxCommandHandler()

        let first = try #require(try handler.add(title: "First", existingItems: [], context: context, deviceID: "test"))
        let second = try #require(try handler.add(title: "Second", existingItems: [first], context: context, deviceID: "test"))
        let third = try #require(try handler.add(title: "Third", existingItems: [first, second], context: context, deviceID: "test"))
        let completed = InboxItem(title: "Completed", isCompleted: true, sortOrder: 5, deviceID: "test")
        context.insert(completed)
        try context.save()

        let reorderedIDs = handler.reorderedOpenItemIDs(
            items: [first, second, third],
            sourceOffsets: IndexSet(integer: 2),
            destination: 0
        )
        try handler.reorderOpenItems(
            orderedItemIDs: reorderedIDs,
            context: context,
            now: Date(timeIntervalSince1970: 4_000)
        )

        let openItems = try context.fetch(
            FetchDescriptor<InboxItem>(
                predicate: #Predicate { $0.deletedAt == nil && $0.isCompleted == false },
                sortBy: [SortDescriptor(\.sortOrder)]
            )
        )
        #expect(openItems.map(\.title) == ["Third", "First", "Second"])
        #expect(openItems.allSatisfy { $0.updatedAt == Date(timeIntervalSince1970: 4_000) })
        #expect(completed.sortOrder == 5)
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
    func pomodoroCommandHandlerCancelsRunForStoppedSession() throws {
        let context = try makeTestContext()
        let sessionID = UUID()
        let run = PomodoroRun(taskID: UUID(), deviceID: "test")
        run.sessionID = sessionID
        run.state = .focusing
        context.insert(run)
        try context.save()

        let handler = PomodoroCommandHandler()
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

}
