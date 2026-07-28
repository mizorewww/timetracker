import Foundation
import SwiftData
import Testing
@testable import timetracker

@Suite(.serialized)
struct CoreSystemActionCommandTests {
    @Test @MainActor
    func stopAllTimersMutationStopsEveryRunningSegment() throws {
        let context = try makeTestContext()
        let task = try SwiftDataTaskRepository(
            context: context,
            deviceID: "test"
        ).createTask(
            title: "Parallel work",
            parentID: nil,
            colorHex: nil,
            iconName: nil
        )
        let first = TimeSegment(
            sessionID: UUID(),
            taskID: task.id,
            source: .timer,
            deviceID: "test",
            startedAt: Date(timeIntervalSinceReferenceDate: 100)
        )
        let second = TimeSegment(
            sessionID: UUID(),
            taskID: task.id,
            source: .pomodoro,
            deviceID: "test",
            startedAt: Date(timeIntervalSinceReferenceDate: 200)
        )
        context.insert(first)
        context.insert(second)
        try context.save()

        let outcome = try makeTestSystemActionCommandHandler()
            .stopAllTimersMutation(container: context.container)

        #expect(outcome.didMutate)
        #expect(Set(outcome.stoppedSegmentIDs) == Set([first.id, second.id]))
        #expect(outcome.events.isEmpty == false)
        let remaining = try SwiftDataTimeTrackingRepository(context: context)
            .activeSegments()
        #expect(remaining.isEmpty)
    }

    @Test @MainActor
    func committedSystemActionRefreshesEveryConfiguredSceneWithoutStartingSuggestions() async throws {
        let context = try makeTestContext()
        let task = try SwiftDataTaskRepository(
            context: context,
            deviceID: "test"
        ).createTask(
            title: "Externally tracked",
            parentID: nil,
            colorHex: nil,
            iconName: nil
        )
        let firstScene = makeTestStore()
        let secondScene = makeTestStore()
        let secondContext = ModelContext(context.container)
        firstScene.configureRepositoriesIfNeeded(context: context)
        secondScene.configureRepositoriesIfNeeded(context: secondContext)
        try firstScene.refresh()
        try secondScene.refresh()
        firstScene.installStoreMutationObserverIfNeeded()
        secondScene.installStoreMutationObserverIfNeeded()
        defer {
            firstScene.removeStoreMutationObserver()
            secondScene.removeStoreMutationObserver()
        }

        let handler = makeTestSystemActionCommandHandler()
        let started = try handler.startTimerMutation(
            taskID: task.id,
            source: .shortcut,
            container: context.container
        )
        let segmentID = try #require(started.subjectSegmentID)
        StoreMutationBroadcaster.publish(events: started.events)
        await StoreMutationBroadcaster.waitUntilIdle()

        #expect(firstScene.activeSegments.map(\.id) == [segmentID])
        #expect(secondScene.activeSegments.map(\.id) == [segmentID])
        #expect(firstScene.inboxSuggestionInFlightIDs.isEmpty)
        #expect(secondScene.inboxSuggestionInFlightIDs.isEmpty)

        let stopped = try handler.stopTimerMutation(
            segmentID: segmentID,
            container: context.container
        )
        StoreMutationBroadcaster.publish(events: stopped.events)
        await StoreMutationBroadcaster.waitUntilIdle()

        #expect(firstScene.activeSegments.isEmpty)
        #expect(secondScene.activeSegments.isEmpty)
    }

    @Test @MainActor
    func committedLocalInboxMutationRefreshesOtherScenesWithoutStartingSuggestions() async throws {
        let context = try makeTestContext()
        _ = try SwiftDataTaskRepository(
            context: context,
            deviceID: "test"
        ).createTask(
            title: "Shared task",
            parentID: nil,
            colorHex: nil,
            iconName: nil
        )
        let firstScene = makeTestStore()
        let delayedInboxService = LLMInboxSuggestionService { _ in
            try await Task.sleep(for: .seconds(5))
            throw CancellationError()
        }
        let secondScene = TimeTrackerStore(
            inboxSuggestionService: delayedInboxService,
            writeAuthorization: .isolatedTestHarness
        )
        firstScene.configureRepositoriesIfNeeded(context: context)
        secondScene.configureRepositoriesIfNeeded(context: ModelContext(context.container))
        try firstScene.refresh()
        try secondScene.refresh()
        secondScene.preferences.llmEndpoint = "https://example.test/v1"
        secondScene.preferences.llmAPIKey = "test-key"
        secondScene.preferences.llmSelectedModel = "test-model"
        secondScene.preferences.llmAutomaticSuggestionsEnabled = true
        firstScene.installStoreMutationObserverIfNeeded()
        secondScene.installStoreMutationObserverIfNeeded()
        defer {
            firstScene.removeStoreMutationObserver()
            secondScene.removeStoreMutationObserver()
            secondScene.cancelAllInboxSuggestionRequests()
        }

        #expect(firstScene.addInboxItem(title: "Visible everywhere"))
        await StoreMutationBroadcaster.waitUntilIdle()

        #expect(secondScene.openInboxItems.map(\.title) == ["Visible everywhere"])
        #expect(firstScene.inboxSuggestionInFlightIDs.isEmpty)
        #expect(secondScene.inboxSuggestionInFlightIDs.isEmpty)
        #expect(firstScene.checklistVisualSuggestionInFlightIDs.isEmpty)
        #expect(secondScene.checklistVisualSuggestionInFlightIDs.isEmpty)
    }

    @Test @MainActor
    func committedLocalTaskArchiveClearsOtherSceneSelectionAndRoute() async throws {
        let context = try makeTestContext()
        let repository = SwiftDataTaskRepository(context: context, deviceID: "test")
        let retainedTask = try repository.createTask(
            title: "Retained task",
            parentID: nil,
            colorHex: nil,
            iconName: nil
        )
        let archivedTask = try repository.createTask(
            title: "Archived task",
            parentID: nil,
            colorHex: nil,
            iconName: nil
        )
        let firstScene = makeTestStore()
        let secondScene = makeTestStore()
        firstScene.configureRepositoriesIfNeeded(context: context)
        secondScene.configureRepositoriesIfNeeded(context: ModelContext(context.container))
        try firstScene.refresh()
        try secondScene.refresh()
        secondScene.openTaskDetail(archivedTask.id)
        firstScene.installStoreMutationObserverIfNeeded()
        secondScene.installStoreMutationObserverIfNeeded()
        defer {
            firstScene.removeStoreMutationObserver()
            secondScene.removeStoreMutationObserver()
        }

        #expect(firstScene.archiveSelectedTask(taskID: archivedTask.id))
        await StoreMutationBroadcaster.waitUntilIdle()

        let synchronizedTask = try #require(secondScene.task(for: archivedTask.id))
        #expect(synchronizedTask.isArchivedForLifecycle)
        #expect(secondScene.isTaskVisible(synchronizedTask) == false)
        #expect(secondScene.selectedTaskID == retainedTask.id)
        #expect(secondScene.tasksRoute == nil)
    }

    @Test @MainActor
    func systemActionAddInboxItemUsesStoreScopedCoordinator() throws {
        let context = try makeTestContext()
        let handler = makeTestSystemActionCommandHandler()
        let source = try sourceText("timetracker/Commands/SystemActionCommands.swift")

        #expect(source.contains("StoreScopedInboxCommandCoordinator("))
        #expect(source.contains("container: ModelContainer"))
        #expect(source.contains("InboxCommandHandler()\n                .add") == false)

        let outcome = try handler.addInboxItem(
            title: "Capture from shortcut",
            container: context.container,
            deviceID: "test"
        )
        let itemID = try #require(outcome.affectedItemIDs.first)

        #expect(outcome.didMutate)
        let items = try context.fetch(FetchDescriptor<InboxItem>())
        #expect(items.map(\.id) == [itemID])
        #expect(items.map(\.title) == ["Capture from shortcut"])
        #expect(items.map(\.deviceID) == ["test"])
    }

    @Test @MainActor
    func explicitExternalInboxKeyReplaysTheCommittedOutcomeWithoutAnotherMutation() throws {
        let context = try makeTestContext()
        let key = try ExternalCommandKey(origin: "test.integration", id: UUID())
        let handler = makeTestSystemActionCommandHandler()

        let first = try handler.addInboxItem(
            title: "Capture once",
            container: context.container,
            externalCommandKey: key,
            deviceID: "test"
        )
        let replay = try handler.addInboxItem(
            title: "Capture once",
            container: context.container,
            externalCommandKey: key,
            deviceID: "test"
        )

        #expect(first.didMutate)
        #expect(replay.didMutate == false)
        #expect(replay.affectedItemIDs == first.affectedItemIDs)
        #expect(try context.fetch(FetchDescriptor<InboxItem>()).count == 1)
        #expect(try context.fetch(FetchDescriptor<InboxCaptureReceipt>()).count == 1)
    }

    @Test @MainActor
    func systemActionStartTimerCreatesTimerLedgerSegment() throws {
        let context = try makeTestContext()
        let taskRepository = SwiftDataTaskRepository(context: context, deviceID: "test")
        let task = try taskRepository.createTask(title: "Shortcut task", parentID: nil, colorHex: nil, iconName: nil)
        let handler = makeTestSystemActionCommandHandler()

        let segmentID = try #require(try handler.startTimer(
            taskID: task.id,
            context: context
        ))

        let segments = try context.fetch(FetchDescriptor<TimeSegment>())
        #expect(segments.map(\.id) == [segmentID])
        #expect(segments.map(\.taskID) == [task.id])
        #expect(segments.map(\.source) == [.timer])
        #expect(segments.first?.endedAt == nil)
    }

    @Test @MainActor
    func shortcutTimerSourceIsPersistedByTheSerializedCommand() throws {
        let context = try makeTestContext()
        let task = try SwiftDataTaskRepository(
            context: context,
            deviceID: "test"
        ).createTask(
            title: "Shortcut source",
            parentID: nil,
            colorHex: nil,
            iconName: nil
        )

        let outcome = try makeTestSystemActionCommandHandler().startTimerMutation(
            taskID: task.id,
            source: .shortcut,
            container: context.container
        )

        let freshRepository = SwiftDataTimeTrackingRepository(
            context: ModelContext(context.container),
            deviceID: "test"
        )
        let segment = try #require(try freshRepository.activeSegments().first)
        #expect(segment.id == outcome.subjectSegmentID)
        #expect(segment.source == .shortcut)
    }

    @Test @MainActor
    func shortcutRapidRestartCoalescesThroughSystemActionCommands() throws {
        let context = try makeTestContext()
        let task = try SwiftDataTaskRepository(
            context: context,
            deviceID: "test"
        ).createTask(
            title: "Shortcut rapid restart",
            parentID: nil,
            colorHex: nil,
            iconName: nil
        )
        let handler = makeTestSystemActionCommandHandler()
        let first = try handler.startTimerMutation(
            taskID: task.id,
            source: .shortcut,
            container: context.container
        )
        let predecessorID = try #require(first.subjectSegmentID)
        let fixtureContext = ModelContext(context.container)
        let predecessor = try #require(
            try fixtureContext.fetch(FetchDescriptor<TimeSegment>())
                .first { $0.id == predecessorID }
        )
        let session = try #require(
            try fixtureContext.fetch(FetchDescriptor<TimeSession>())
                .first { $0.id == predecessor.sessionID }
        )
        let sessionID = session.id
        let backdatedStart = Date().addingTimeInterval(-120)
        predecessor.startedAt = backdatedStart
        session.startedAt = backdatedStart
        try fixtureContext.save()

        let stopped = try handler.stopTimerMutation(
            segmentID: predecessorID,
            container: context.container
        )
        let restarted = try handler.startTimerMutation(
            taskID: task.id,
            source: .shortcut,
            container: context.container
        )

        let replacementID = try #require(restarted.subjectSegmentID)
        #expect(stopped.subjectSegmentID == predecessorID)
        #expect(
            replacementID == TimerRapidRestartPolicy()
                .replacementSegmentID(predecessorSegmentID: predecessorID)
        )
        #expect(restarted.tombstonedSegments.map(\.segmentID) == [predecessorID])
        let verificationContext = ModelContext(context.container)
        let rawSegments = try verificationContext.fetch(
            FetchDescriptor<TimeSegment>()
        )
        let visibleSegments = try SwiftDataTimeTrackingRepository(
            context: verificationContext,
            deviceID: "test"
        ).allSegments()
        #expect(rawSegments.count == 2)
        #expect(rawSegments.first { $0.id == predecessorID }?.deletedAt != nil)
        #expect(visibleSegments.map(\.id) == [replacementID])
        #expect(visibleSegments.first?.sessionID == sessionID)
        #expect(visibleSegments.first?.startedAt == backdatedStart)
        #expect(visibleSegments.first?.source == .shortcut)
        #expect(visibleSegments.first?.endedAt == nil)
    }

    @Test @MainActor
    func systemActionExistingTimerStillReconcilesUnexpectedParallelTimers() throws {
        let context = try makeTestContext()
        let taskRepository = SwiftDataTaskRepository(context: context, deviceID: "test")
        let timeRepository = SwiftDataTimeTrackingRepository(context: context, deviceID: "test")
        let selectedTask = try taskRepository.createTask(
            title: "Selected",
            parentID: nil,
            colorHex: nil,
            iconName: nil
        )
        let otherTask = try taskRepository.createTask(
            title: "Other",
            parentID: nil,
            colorHex: nil,
            iconName: nil
        )
        let selectedSegment = try timeRepository.startTask(taskID: selectedTask.id, source: .timer)
        let otherSegment = try timeRepository.startTask(taskID: otherTask.id, source: .timer)
        try PreferenceCommandHandler().set(
            key: .allowParallelTimers,
            valueJSON: PreferenceJSON.encode(false),
            context: context
        )

        let returnedID = try makeTestSystemActionCommandHandler().startTimer(
            taskID: selectedTask.id,
            context: context
        )

        #expect(returnedID == selectedSegment.id)
        let freshRepository = SwiftDataTimeTrackingRepository(
            context: ModelContext(context.container),
            deviceID: "test"
        )
        #expect(try freshRepository.activeSegments().map(\.id) == [selectedSegment.id])
        #expect(
            try freshRepository.allSegments().first { $0.id == otherSegment.id }?.endedAt
                != nil
        )
        #expect(try freshRepository.allSegments().count == 2)
    }

    @Test @MainActor
    func mutationOutcomePublishesBothStoppedAndStartedTimerDomains() {
        let stopped = TimerMutationSegmentSnapshot(
            segmentID: UUID(),
            sessionID: UUID(),
            taskID: UUID()
        )
        let started = TimerMutationSegmentSnapshot(
            segmentID: UUID(),
            sessionID: UUID(),
            taskID: UUID()
        )
        let events = StoreScopedTimerCommandOutcome(
            subjectSegment: started,
            createdSegment: started,
            stoppedSegments: [stopped]
        ).events

        #expect(events.contains(.ledgerChanged(taskID: stopped.taskID, dateInterval: nil, isVisible: true)))
        #expect(events.contains(.pomodoroChanged(
            runID: nil,
            sessionID: stopped.sessionID,
            taskID: stopped.taskID
        )))
        #expect(events.contains(.ledgerChanged(taskID: started.taskID, dateInterval: nil, isVisible: true)))
        #expect(events.contains(.pomodoroChanged(
            runID: nil,
            sessionID: started.sessionID,
            taskID: started.taskID
        )))
        #expect(events.count == 4)
    }

    @Test @MainActor
    func mutationOutcomePublishesRapidRestartHistoryInvalidation() {
        let taskID = UUID()
        let sessionID = UUID()
        let startedAt = Date(timeIntervalSinceReferenceDate: 300_000)
        let stoppedAt = startedAt.addingTimeInterval(120)
        let predecessor = TimeSegment(
            sessionID: sessionID,
            taskID: taskID,
            source: .timer,
            deviceID: "test",
            startedAt: startedAt,
            endedAt: stoppedAt
        )
        let tombstone = LedgerSegmentMutationSnapshot(segment: predecessor)
        let replacement = TimerMutationSegmentSnapshot(
            segmentID: UUID(),
            sessionID: sessionID,
            taskID: taskID
        )
        let outcome = StoreScopedTimerCommandOutcome(
            subjectSegment: replacement,
            createdSegment: replacement,
            stoppedSegments: [],
            tombstonedSegments: [tombstone]
        )

        #expect(outcome.didMutate)
        #expect(outcome.referencedTaskIDs == [taskID])
        #expect(outcome.events.contains(.ledgerChanged(
            taskID: taskID,
            dateInterval: StoreInvalidationRange(
                start: startedAt,
                end: stoppedAt
            ),
            isVisible: false
        )))
        #expect(outcome.events.contains(.ledgerChanged(
            taskID: taskID,
            dateInterval: nil,
            isVisible: true
        )))
    }

    @Test @MainActor
    func systemActionCannotRestartAnArchivedTaskFromAStaleShortcut() throws {
        let context = try makeTestContext()
        let taskRepository = SwiftDataTaskRepository(context: context, deviceID: "test")
        let task = try taskRepository.createTask(
            title: "Archived shortcut task",
            parentID: nil,
            colorHex: nil,
            iconName: nil
        )
        try taskRepository.archiveTask(taskID: task.id)

        #expect(throws: SystemActionCommandError.taskNotFound) {
            try makeTestSystemActionCommandHandler().startTimer(
                taskID: task.id,
                context: context
            )
        }
        #expect(try context.fetch(FetchDescriptor<TimeSegment>()).isEmpty)
    }

    @Test @MainActor
    func systemActionCannotStartAChildWhoseAncestorIsArchived() throws {
        let context = try makeTestContext()
        let taskRepository = SwiftDataTaskRepository(context: context, deviceID: "test")
        let parent = try taskRepository.createTask(
            title: "Archived parent",
            parentID: nil,
            colorHex: nil,
            iconName: nil
        )
        let child = try taskRepository.createTask(
            title: "Previously active child",
            parentID: parent.id,
            colorHex: nil,
            iconName: nil
        )
        try taskRepository.archiveTask(taskID: parent.id)

        #expect(throws: SystemActionCommandError.taskNotFound) {
            try makeTestSystemActionCommandHandler().startTimer(
                taskID: child.id,
                context: context
            )
        }
        #expect(child.statusRaw == LegacyTaskStatusRaw.active)
        #expect(try context.fetch(FetchDescriptor<TimeSegment>()).isEmpty)
    }

    @Test @MainActor
    func systemActionCannotStartHealthSyncTaskOrStopAnotherTimer() throws {
        let context = try makeTestContext()
        let taskRepository = SwiftDataTaskRepository(
            context: context,
            deviceID: "test"
        )
        let ordinary = try taskRepository.createTask(
            title: "Keep running",
            parentID: nil,
            colorHex: nil,
            iconName: nil
        )
        let healthTask = TaskNode(
            title: "Imported workout",
            parentID: nil,
            deviceID: "health"
        )
        healthTask.id = AppleHealthTaskCatalog.taskDefinition(
            for: .workout(.running)
        ).id
        context.insert(healthTask)
        try context.save()

        let timeRepository = SwiftDataTimeTrackingRepository(
            context: context,
            deviceID: "test"
        )
        let active = try timeRepository.startTask(
            taskID: ordinary.id,
            source: .timer
        )

        #expect(throws: SystemActionCommandError.taskNotFound) {
            try makeTestSystemActionCommandHandler().startTimer(
                taskID: healthTask.id,
                context: context
            )
        }
        #expect(try timeRepository.activeSegments().map(\.id) == [active.id])
    }

    @Test @MainActor
    func systemActionStopTimerClosesActiveSegment() throws {
        let context = try makeTestContext()
        let taskRepository = SwiftDataTaskRepository(context: context, deviceID: "test")
        let timeRepository = SwiftDataTimeTrackingRepository(context: context, deviceID: "test")
        let task = try taskRepository.createTask(title: "Running task", parentID: nil, colorHex: nil, iconName: nil)
        let segment = try timeRepository.startTask(taskID: task.id, source: .timer)
        let handler = makeTestSystemActionCommandHandler()

        let stoppedID = try #require(try handler.stopTimer(taskID: task.id, context: context))

        #expect(stoppedID == segment.id)
        let stoppedSegment = try #require(try timeRepository.allSegments().first)
        #expect(stoppedSegment.endedAt != nil)
    }

    @Test @MainActor
    func untargetedSystemStopRejectsParallelTimers() throws {
        let context = try makeTestContext()
        let taskRepository = SwiftDataTaskRepository(context: context, deviceID: "test")
        let timeRepository = SwiftDataTimeTrackingRepository(context: context, deviceID: "test")
        let olderTask = try taskRepository.createTask(
            title: "Older timer task",
            parentID: nil,
            colorHex: nil,
            iconName: nil
        )
        let newerTask = try taskRepository.createTask(
            title: "Newer timer task",
            parentID: nil,
            colorHex: nil,
            iconName: nil
        )
        let older = try timeRepository.startTask(taskID: olderTask.id, source: .timer)
        let newer = try timeRepository.startTask(taskID: newerTask.id, source: .timer)
        older.startedAt = Date(timeIntervalSinceReferenceDate: 100)
        newer.startedAt = Date(timeIntervalSinceReferenceDate: 200)
        try context.save()

        let stoppedID = try makeTestSystemActionCommandHandler().stopTimer(taskID: nil, context: context)

        #expect(stoppedID == nil)
        #expect(older.endedAt == nil)
        #expect(newer.endedAt == nil)
        #expect(try Set(timeRepository.activeSegments().map(\.id)) == [older.id, newer.id])
    }

    @Test @MainActor
    func untargetedSystemStopRemainsCompatibleForOneTimer() throws {
        let context = try makeTestContext()
        let taskRepository = SwiftDataTaskRepository(context: context, deviceID: "test")
        let timeRepository = SwiftDataTimeTrackingRepository(context: context, deviceID: "test")
        let task = try taskRepository.createTask(
            title: "Only timer",
            parentID: nil,
            colorHex: nil,
            iconName: nil
        )
        let segment = try timeRepository.startTask(taskID: task.id, source: .timer)

        let stoppedID = try makeTestSystemActionCommandHandler().stopTimer(context: context)

        #expect(stoppedID == segment.id)
        #expect(try timeRepository.activeSegments().isEmpty)
    }

    @Test @MainActor
    func segmentTargetStopsOnlyTheSerializedParallelTimer() throws {
        let context = try makeTestContext()
        let taskRepository = SwiftDataTaskRepository(context: context, deviceID: "test")
        let timeRepository = SwiftDataTimeTrackingRepository(context: context, deviceID: "test")
        let firstTask = try taskRepository.createTask(title: "First", parentID: nil, colorHex: nil, iconName: nil)
        let secondTask = try taskRepository.createTask(title: "Second", parentID: nil, colorHex: nil, iconName: nil)
        let first = try timeRepository.startTask(taskID: firstTask.id, source: .timer)
        let second = try timeRepository.startTask(taskID: secondTask.id, source: .timer)

        let stoppedID = try makeTestSystemActionCommandHandler().stopTimer(
            segmentID: first.id,
            context: context
        )

        #expect(stoppedID == first.id)
        let freshRepository = SwiftDataTimeTrackingRepository(
            context: ModelContext(context.container),
            deviceID: "test"
        )
        let persistedSegments = try freshRepository.allSegments()
        #expect(persistedSegments.first { $0.id == first.id }?.endedAt != nil)
        #expect(persistedSegments.first { $0.id == second.id }?.endedAt == nil)
        #expect(try freshRepository.activeSegments().map(\.id) == [second.id])
    }

    @Test @MainActor
    func targetedSystemStopDoesNotFallBackToAnUnrelatedActiveTimer() throws {
        let context = try makeTestContext()
        let taskRepository = SwiftDataTaskRepository(context: context, deviceID: "test")
        let timeRepository = SwiftDataTimeTrackingRepository(context: context, deviceID: "test")
        let staleTarget = try taskRepository.createTask(
            title: "Already stopped",
            parentID: nil,
            colorHex: nil,
            iconName: nil
        )
        let runningTask = try taskRepository.createTask(
            title: "Still running",
            parentID: nil,
            colorHex: nil,
            iconName: nil
        )
        let runningSegment = try timeRepository.startTask(taskID: runningTask.id, source: .timer)

        let stoppedID = try makeTestSystemActionCommandHandler().stopTimer(
            taskID: staleTarget.id,
            context: context
        )

        #expect(stoppedID == nil)
        #expect(try timeRepository.activeSegments().map(\.id) == [runningSegment.id])
    }

    @Test @MainActor
    func systemActionStopClipsExpiredPomodoroToPersistedDeadline() throws {
        let context = try makeTestContext()
        let taskRepository = SwiftDataTaskRepository(context: context, deviceID: "test")
        let timeRepository = SwiftDataTimeTrackingRepository(context: context, deviceID: "test")
        let pomodoroRepository = SwiftDataPomodoroRepository(
            context: context,
            timeRepository: timeRepository,
            deviceID: "test"
        )
        let task = try taskRepository.createTask(
            title: "Expired shortcut focus",
            parentID: nil,
            colorHex: nil,
            iconName: nil
        )
        let run = try pomodoroRepository.startPomodoro(
            taskID: task.id,
            focusSeconds: 60,
            breakSeconds: 30,
            targetRounds: 1
        )
        let sessionID = try #require(run.sessionID)
        let segment = try #require(try timeRepository.activeSegments().first { $0.sessionID == sessionID })
        let session = try #require(try timeRepository.sessions().first { $0.id == sessionID })
        let phaseStartedAt = Date().addingTimeInterval(-120)
        let deadline = phaseStartedAt.addingTimeInterval(60)
        run.startedAt = phaseStartedAt
        segment.startedAt = phaseStartedAt
        session.startedAt = phaseStartedAt
        try context.save()

        let stoppedID = try #require(
            try makeTestSystemActionCommandHandler().stopTimer(taskID: task.id, context: context)
        )

        let persistedRun = try #require(try pomodoroRepository.runs().first { $0.id == run.id })
        let persistedSegment = try #require(try timeRepository.allSegments().first { $0.id == segment.id })
        let persistedSession = try #require(try timeRepository.sessions().first { $0.id == sessionID })
        #expect(stoppedID == segment.id)
        #expect(persistedRun.state == .completed)
        #expect(persistedRun.endedAt == deadline)
        #expect(persistedSegment.endedAt == deadline)
        #expect(persistedSession.endedAt == deadline)
    }

    @Test @MainActor
    func timerAdmissionReadsTheSyncedParallelTimerPreference() throws {
        let context = try makeTestContext()
        try PreferenceCommandHandler().set(
            key: .allowParallelTimers,
            valueJSON: PreferenceJSON.encode(false),
            context: context
        )

        #expect(
            try TimerAdmissionPreferenceResolver.allowParallelTimers(in: context) == false
        )
    }
}
