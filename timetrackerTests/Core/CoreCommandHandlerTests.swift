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
    func checklistMutationsRecordTheCurrentDeviceAsTheLatestWriter() throws {
        let context = try makeTestContext()
        let taskID = UUID()
        let handler = ChecklistCommandHandler()
        let first = try #require(
            try handler.add(
                taskID: taskID,
                title: "First",
                existingItems: [],
                context: context,
                deviceID: "local-device"
            )
        )
        let second = try #require(
            try handler.add(
                taskID: taskID,
                title: "Second",
                existingItems: [first],
                context: context,
                deviceID: "local-device"
            )
        )
        let visuals = try context.fetch(FetchDescriptor<ChecklistItemVisual>())
        let firstVisual = try #require(visuals.first { $0.checklistItemID == first.id })
        let secondVisual = try #require(visuals.first { $0.checklistItemID == second.id })

        first.deviceID = "remote-device"
        try context.save()
        try handler.toggle(
            first,
            context: context,
            now: Date(timeIntervalSinceReferenceDate: 1_000),
            deviceID: "local-device"
        )
        #expect(first.deviceID == "local-device")

        first.deviceID = "remote-device"
        second.deviceID = "remote-device"
        try context.save()
        try handler.reorder(
            taskID: taskID,
            orderedItemIDs: [second.id, first.id],
            context: context,
            deviceID: "local-device"
        )
        #expect(first.deviceID == "local-device")
        #expect(second.deviceID == "local-device")

        firstVisual.deviceID = "remote-device"
        try context.save()
        try handler.applyVisualSuggestion(
            item: first,
            result: LLMChecklistVisualSuggestionResult(
                iconName: "book",
                colorHex: "16A34A",
                reason: "Matches reading",
                modelID: "test-model"
            ),
            existingVisual: firstVisual,
            context: context,
            deviceID: "local-device"
        )
        #expect(firstVisual.deviceID == "local-device")

        for item in [first, second] {
            item.deviceID = "remote-device"
        }
        for visual in [firstVisual, secondVisual] {
            visual.deviceID = "remote-device"
        }
        try context.save()
        try ChecklistDraftService().save(
            drafts: [ChecklistEditorDraft(item: first, visual: firstVisual)],
            taskID: taskID,
            context: context,
            deviceID: "local-device"
        )

        #expect(first.deviceID == "local-device")
        #expect(firstVisual.deviceID == "local-device")
        #expect(second.deletedAt != nil)
        #expect(second.deviceID == "local-device")
        #expect(secondVisual.deletedAt != nil)
        #expect(secondVisual.deviceID == "local-device")
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
    func checklistDraftServiceRejectsNthInvalidDraftBeforeMutatingEarlierItems() throws {
        let context = try makeTestContext()
        let taskID = UUID()
        let originalDate = Date(timeIntervalSinceReferenceDate: 100_000)
        let originalMutationID = UUID()
        let item = ChecklistItem(
            taskID: taskID,
            title: "Original",
            isCompleted: false,
            sortOrder: 30,
            deviceID: "original-device"
        )
        item.updatedAt = originalDate
        item.clientMutationID = originalMutationID
        let visual = ChecklistItemVisual(
            checklistItemID: item.id,
            iconName: "book",
            colorHex: "16A34A",
            deviceID: "original-device"
        )
        visual.updatedAt = originalDate
        context.insert(item)
        context.insert(visual)
        try context.save()

        var validFirstDraft = ChecklistEditorDraft(item: item, visual: visual)
        validFirstDraft.title = "Changed too early"
        validFirstDraft.isCompleted = true
        validFirstDraft.iconName = "paintbrush"
        validFirstDraft.colorHex = "EF4444"

        #expect(throws: ChecklistDraftValidationError.emptyTitle(index: 1)) {
            try ChecklistDraftService().save(
                drafts: [validFirstDraft, ChecklistEditorDraft(title: "   ")],
                taskID: taskID,
                context: context,
                deviceID: "new-device"
            )
        }

        let persistedItems = try context.fetch(FetchDescriptor<ChecklistItem>())
        let persistedVisuals = try context.fetch(FetchDescriptor<ChecklistItemVisual>())
        let persistedItem = try #require(persistedItems.first { $0.id == item.id })
        let persistedVisual = try #require(persistedVisuals.first { $0.id == visual.id })
        #expect(persistedItems.count == 1)
        #expect(persistedVisuals.count == 1)
        #expect(persistedItem.title == "Original")
        #expect(persistedItem.isCompleted == false)
        #expect(persistedItem.completedAt == nil)
        #expect(persistedItem.sortOrder == 30)
        #expect(persistedItem.updatedAt == originalDate)
        #expect(persistedItem.clientMutationID == originalMutationID)
        #expect(persistedItem.deviceID == "original-device")
        #expect(persistedVisual.iconName == "book")
        #expect(persistedVisual.colorHex == "16A34A")
        #expect(persistedVisual.updatedAt == originalDate)
    }

    @Test @MainActor
    func checklistDraftServiceUsesUTF8LimitsAndPreservesVisualSanitization() throws {
        let context = try makeTestContext()
        let maximum = ChecklistDraftPersistencePolicy.maximumTitleByteCount
        let exactTitle = String(repeating: "界", count: maximum / 3) + "a"
        #expect(exactTitle.utf8.count == maximum)

        try ChecklistDraftService().save(
            drafts: [
                ChecklistEditorDraft(
                    title: exactTitle,
                    iconName: "  book  ",
                    colorHex: "#1677ff"
                )
            ],
            taskID: UUID(),
            context: context,
            deviceID: "test"
        )

        let item = try #require(try context.fetch(FetchDescriptor<ChecklistItem>()).first)
        let visual = try #require(try context.fetch(FetchDescriptor<ChecklistItemVisual>()).first)
        #expect(item.title == exactTitle)
        #expect(item.title.utf8.count == SyncDataSnapshotRestoreLimits.maximumTitleByteCount)
        #expect(visual.iconName == "book")
        #expect(visual.colorHex == "1677FF")
        #expect(visual.iconName.utf8.count <= SyncDataSnapshotRestoreLimits.maximumCompactFieldByteCount)
        #expect(visual.colorHex.utf8.count <= SyncDataSnapshotRestoreLimits.maximumCompactFieldByteCount)
    }

    @Test @MainActor
    func checklistDraftServiceRejectsOversizedMultibyteTextWithoutPartialWrites() throws {
        let context = try makeTestContext()
        let taskID = UUID()
        let original = ChecklistItem(taskID: taskID, title: "Original", sortOrder: 10, deviceID: "test")
        context.insert(original)
        try context.save()

        var validFirstDraft = ChecklistEditorDraft(item: original)
        validFirstDraft.title = "Should stay original"
        let maximum = ChecklistDraftPersistencePolicy.maximumTitleByteCount
        let oversizedTitle = String(repeating: "界", count: maximum / 3 + 1)
        #expect(oversizedTitle.utf8.count > maximum)

        #expect(throws: ChecklistDraftValidationError.byteLimitExceeded(
            index: 1,
            field: .title,
            actual: oversizedTitle.utf8.count,
            maximum: maximum
        )) {
            try ChecklistDraftService().save(
                drafts: [validFirstDraft, ChecklistEditorDraft(title: oversizedTitle)],
                taskID: taskID,
                context: context,
                deviceID: "test"
            )
        }

        let persistedItems = try context.fetch(FetchDescriptor<ChecklistItem>())
        let persisted = try #require(persistedItems.first { $0.id == original.id })
        #expect(persistedItems.count == 1)
        #expect(persisted.title == "Original")
        #expect(persisted.sortOrder == 10)
    }

    @Test @MainActor
    func checklistDraftServiceRejectsControlCharactersInEveryPersistedDraftField() throws {
        let context = try makeTestContext()
        var invalidTitle = ChecklistEditorDraft(title: "Valid")
        invalidTitle.title = "Invalid\u{0}title"
        var invalidIcon = ChecklistEditorDraft(title: "Valid")
        invalidIcon.iconName = "book\t"
        var invalidColor = ChecklistEditorDraft(title: "Valid")
        invalidColor.colorHex = "1677FF\n"

        let cases: [(ChecklistDraftField, ChecklistEditorDraft)] = [
            (.title, invalidTitle),
            (.iconName, invalidIcon),
            (.colorHex, invalidColor)
        ]
        for (field, draft) in cases {
            #expect(throws: ChecklistDraftValidationError.controlCharacter(index: 0, field: field)) {
                try ChecklistDraftService().save(
                    drafts: [draft],
                    taskID: UUID(),
                    context: context,
                    deviceID: "test"
                )
            }
        }

        #expect(try context.fetch(FetchDescriptor<ChecklistItem>()).isEmpty)
        #expect(try context.fetch(FetchDescriptor<ChecklistItemVisual>()).isEmpty)
    }

    @Test @MainActor
    func checklistDraftServiceRollsBackWhenPersistentSaveFails() throws {
        let storeDirectory = FileManager.default.temporaryDirectory.appending(
            path: "ChecklistDraftAtomicTests-\(UUID().uuidString)",
            directoryHint: .isDirectory
        )
        try FileManager.default.createDirectory(at: storeDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: storeDirectory) }
        let storeURL = storeDirectory.appending(path: "checklist.store")
        let schema = TimeTrackerModelRegistry.currentSchema
        let taskID = UUID()
        let itemID = UUID()
        let visualID = UUID()
        let originalDate = Date(timeIntervalSinceReferenceDate: 200_000)
        let originalItemMutationID = UUID()
        let originalVisualMutationID = UUID()

        try initializeChecklistStore(
            at: storeURL,
            schema: schema,
            taskID: taskID,
            itemID: itemID,
            visualID: visualID,
            updatedAt: originalDate,
            itemMutationID: originalItemMutationID,
            visualMutationID: originalVisualMutationID
        )
        let readOnlyContainer = try makeReadOnlyChecklistContainer(at: storeURL, schema: schema)
        let context = ModelContext(readOnlyContainer)
        let item = try #require(
            try context.fetch(FetchDescriptor<ChecklistItem>()).first { $0.id == itemID }
        )
        let visual = try #require(
            try context.fetch(FetchDescriptor<ChecklistItemVisual>()).first { $0.id == visualID }
        )
        var draft = ChecklistEditorDraft(item: item, visual: visual)
        draft.title = "Changed"
        draft.isCompleted = true
        draft.iconName = "paintbrush"
        draft.colorHex = "EF4444"

        #expect(throws: (any Error).self) {
            try ChecklistDraftService().save(
                drafts: [draft],
                taskID: taskID,
                context: context,
                deviceID: "new-device"
            )
        }

        let persistedItems = try context.fetch(FetchDescriptor<ChecklistItem>())
        let persistedVisuals = try context.fetch(FetchDescriptor<ChecklistItemVisual>())
        let persistedItem = try #require(persistedItems.first { $0.id == itemID })
        let persistedVisual = try #require(persistedVisuals.first { $0.id == visualID })
        #expect(persistedItems.count == 1)
        #expect(persistedVisuals.count == 1)
        #expect(persistedItem.title == "Original")
        #expect(persistedItem.isCompleted == false)
        #expect(persistedItem.completedAt == nil)
        #expect(persistedItem.sortOrder == 20)
        #expect(persistedItem.updatedAt == originalDate)
        #expect(persistedItem.clientMutationID == originalItemMutationID)
        #expect(persistedItem.deviceID == "original-device")
        #expect(persistedVisual.iconName == "book")
        #expect(persistedVisual.colorHex == "16A34A")
        #expect(persistedVisual.updatedAt == originalDate)
        #expect(persistedVisual.clientMutationID == originalVisualMutationID)
        #expect(persistedVisual.deviceID == "original-device")
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
        let taskRepository = SwiftDataTaskRepository(context: context, deviceID: "test")
        let repository = SwiftDataTimeTrackingRepository(context: context, deviceID: "test")
        let firstTask = try taskRepository.createTask(
            title: "First timer task",
            parentID: nil,
            colorHex: nil,
            iconName: nil
        )
        let secondTask = try taskRepository.createTask(
            title: "Second timer task",
            parentID: nil,
            colorHex: nil,
            iconName: nil
        )
        let firstSegment = try repository.startTask(taskID: firstTask.id, source: .timer)

        try TimerCommandHandler().startTask(
            taskID: secondTask.id,
            allowParallelTimers: false,
            activeSegments: [firstSegment],
            pomodoroRuns: [],
            timeRepository: repository,
            context: context
        )

        let activeSegments = try repository.activeSegments()
        #expect(firstSegment.endedAt != nil)
        #expect(activeSegments.count == 1)
        #expect(activeSegments.first?.taskID == secondTask.id)
    }

    @Test @MainActor
    func restartingAnExistingTaskStillReconcilesUnexpectedParallelTimers() throws {
        let context = try makeTestContext()
        let taskRepository = SwiftDataTaskRepository(context: context, deviceID: "test")
        let repository = SwiftDataTimeTrackingRepository(context: context, deviceID: "test")
        let selectedTask = try taskRepository.createTask(
            title: "Selected task",
            parentID: nil,
            colorHex: nil,
            iconName: nil
        )
        let otherTask = try taskRepository.createTask(
            title: "Other task",
            parentID: nil,
            colorHex: nil,
            iconName: nil
        )
        let selectedSegment = try repository.startTask(taskID: selectedTask.id, source: .timer)
        let otherSegment = try repository.startTask(taskID: otherTask.id, source: .timer)

        try TimerCommandHandler().startTask(
            taskID: selectedTask.id,
            allowParallelTimers: false,
            activeSegments: [selectedSegment, otherSegment],
            pomodoroRuns: [],
            timeRepository: repository,
            context: context
        )

        let activeSegments = try repository.activeSegments()
        #expect(activeSegments.map(\.id) == [selectedSegment.id])
        #expect(otherSegment.endedAt != nil)
        #expect(try repository.allSegments().count == 2)
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
    func pomodoroCancellationDefersItsSaveToTheOuterAtomicMutation() throws {
        let context = try makeTestContext()
        let now = Date(timeIntervalSinceReferenceDate: 10_000)
        let taskID = UUID()
        let session = TimeSession(
            taskID: taskID,
            source: .pomodoro,
            deviceID: "test",
            startedAt: now.addingTimeInterval(-50)
        )
        let segment = TimeSegment(
            sessionID: session.id,
            taskID: taskID,
            source: .pomodoro,
            deviceID: "test",
            startedAt: now.addingTimeInterval(-50)
        )
        let run = PomodoroRun(
            taskID: taskID,
            focus: 100,
            breakSeconds: 20,
            deviceID: "test"
        )
        run.sessionID = session.id
        run.state = .focusing
        run.startedAt = session.startedAt
        context.insert(session)
        context.insert(segment)
        context.insert(run)
        try context.save()

        #expect(throws: ForcedCommandFailure.self) {
            try context.performAtomicMutation {
                try PomodoroCommandHandler().cancelIfNeeded(
                    sessionID: session.id,
                    runs: [run],
                    context: context,
                    now: now
                )
                throw ForcedCommandFailure.expected
            }
        }

        let persistedRun = try #require(
            try context.fetch(FetchDescriptor<PomodoroRun>()).first { $0.id == run.id }
        )
        #expect(persistedRun.state == .focusing)
        #expect(persistedRun.endedAt == nil)
    }

    @Test @MainActor
    func timerMutationEventsCoverLedgerAndPomodoroForEveryStoppedTimer() throws {
        let context = try makeTestContext()
        let firstTask = TaskNode(title: "First", parentID: nil, deviceID: "test")
        let secondTask = TaskNode(title: "Second", parentID: nil, deviceID: "test")
        context.insert(firstTask)
        context.insert(secondTask)
        try context.save()
        let timeRepository = SwiftDataTimeTrackingRepository(context: context, deviceID: "test")
        let firstSegment = try timeRepository.startTask(taskID: firstTask.id, source: .pomodoro)

        let store = TimeTrackerStore()
        store.configureIfNeeded(context: context)
        store.preferences.allowParallelTimers = false
        let events = store.timerStartMutationEvents(taskID: secondTask.id)

        #expect(events.contains(.ledgerChanged(taskID: secondTask.id, dateInterval: nil, isVisible: true)))
        #expect(events.contains(.pomodoroChanged(runID: nil, sessionID: nil, taskID: secondTask.id)))
        #expect(events.contains(.ledgerChanged(taskID: firstTask.id, dateInterval: nil, isVisible: true)))
        #expect(events.contains(.pomodoroChanged(
            runID: nil,
            sessionID: firstSegment.sessionID,
            taskID: firstTask.id
        )))
    }

    @Test @MainActor
    func ledgerCommandHandlerOwnsManualSegmentWrites() throws {
        let context = try makeTestContext()
        let repository = SwiftDataTimeTrackingRepository(context: context, deviceID: "test")
        let task = try SwiftDataTaskRepository(context: context, deviceID: "test").createTask(
            title: "Ledger Task",
            parentID: nil,
            colorHex: nil,
            iconName: nil
        )
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

    @MainActor
    private func initializeChecklistStore(
        at url: URL,
        schema: Schema,
        taskID: UUID,
        itemID: UUID,
        visualID: UUID,
        updatedAt: Date,
        itemMutationID: UUID,
        visualMutationID: UUID
    ) throws {
        let configuration = ModelConfiguration(
            "WritableChecklistDraftTests-\(UUID().uuidString)",
            schema: schema,
            url: url,
            cloudKitDatabase: .none
        )
        let container = try ModelContainer(
            for: schema,
            migrationPlan: TimeTrackerMigrationPlan.self,
            configurations: [configuration]
        )
        let context = ModelContext(container)
        let item = ChecklistItem(
            taskID: taskID,
            title: "Original",
            isCompleted: false,
            sortOrder: 20,
            deviceID: "original-device"
        )
        item.id = itemID
        item.updatedAt = updatedAt
        item.clientMutationID = itemMutationID
        let visual = ChecklistItemVisual(
            checklistItemID: itemID,
            iconName: "book",
            colorHex: "16A34A",
            deviceID: "original-device"
        )
        visual.id = visualID
        visual.updatedAt = updatedAt
        visual.clientMutationID = visualMutationID
        context.insert(item)
        context.insert(visual)
        try context.save()
    }

    @MainActor
    private func makeReadOnlyChecklistContainer(at url: URL, schema: Schema) throws -> ModelContainer {
        let configuration = ModelConfiguration(
            "ReadOnlyChecklistDraftTests-\(UUID().uuidString)",
            schema: schema,
            url: url,
            allowsSave: false,
            cloudKitDatabase: .none
        )
        return try ModelContainer(
            for: schema,
            migrationPlan: TimeTrackerMigrationPlan.self,
            configurations: [configuration]
        )
    }

}

private enum ForcedCommandFailure: Error {
    case expected
}
