import Foundation
import SwiftData
import Testing
@testable import timetracker

@Suite(.serialized)
struct CoreSystemActionCommandTests {
    @Test
    func appIntentsAreThinWrappersAroundSystemActionCommands() throws {
        let source = try sourceText("timetracker/AppIntents/TimeTrackerAppIntents.swift")
        let handler = try sourceText("timetracker/Commands/SystemActionCommands.swift")
        let coordinator = try sourceText(
            "timetracker/Services/TimeTracking/StoreScopedTimerCommandCoordinator.swift"
        )

        #expect(source.contains("import AppIntents"))
        #expect(source.contains("struct AddInboxItemIntent: AppIntent"))
        #expect(source.contains("struct StartTimerIntent: AppIntent"))
        #expect(source.contains("extension StartTimerIntent: LiveActivityIntent"))
        #expect(source.contains("struct StopTimerIntent: AppIntent"))
        #expect(source.contains("var timer: ActiveTimerAppEntity"))
        #expect(source.contains("segmentID: targetID"))
        #expect(source.contains(".activeSegments()\n            .last") == false)
        #expect(source.contains("SystemActionCommandHandler()"))
        #expect(source.contains("TimeSegment(") == false)
        #expect(source.contains("TimeSession(") == false)
        #expect(source.contains("context.insert") == false)
        #expect(source.contains("allowParallelTimers") == false)
        #expect(source.contains("source: .shortcut"))
        #expect(source.contains("container: SystemActionContextProvider.container"))
        #expect(source.contains("let postCommitContext = SystemActionContextProvider.makeContext()"))
        #expect(source.contains("timetrackerApp.applicationModelContainer"))
        #expect(
            source.components(
                separatedBy: "await SystemActionPostCommitEffects().apply("
            ).count - 1 == 3
        )
        #expect(handler.contains("struct SystemActionPostCommitEffects"))
        #expect(handler.contains("CommittedMutationSnapshotRecorder().recordLocalMutation"))
        #expect(handler.contains("CommittedMutationSurfaceSynchronizer().synchronize"))
        #expect(handler.contains("await store.waitForLiveActivityReconciliationIfAvailable()"))
        #expect(handler.contains("StoreMutationBroadcaster.publish(events: events)"))
        #expect(handler.contains("allowParallelTimers: Bool") == false)
        #expect(coordinator.contains("TimerAdmissionPreferenceResolver\n                .allowParallelTimers(in: context)"))
    }

    @Test @MainActor
    func committedSystemActionRefreshesEveryConfiguredSceneWithoutStartingSuggestions() throws {
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

        #expect(firstScene.activeSegments.map(\.id) == [segmentID])
        #expect(secondScene.activeSegments.map(\.id) == [segmentID])
        #expect(firstScene.inboxSuggestionInFlightIDs.isEmpty)
        #expect(secondScene.inboxSuggestionInFlightIDs.isEmpty)

        let stopped = try handler.stopTimerMutation(
            segmentID: segmentID,
            container: context.container
        )
        StoreMutationBroadcaster.publish(events: stopped.events)

        #expect(firstScene.activeSegments.isEmpty)
        #expect(secondScene.activeSegments.isEmpty)
    }

    @Test @MainActor
    func committedLocalInboxMutationRefreshesOtherScenesWithoutStartingSuggestions() throws {
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

        #expect(secondScene.openInboxItems.map(\.title) == ["Visible everywhere"])
        #expect(firstScene.inboxSuggestionInFlightIDs.isEmpty)
        #expect(secondScene.inboxSuggestionInFlightIDs.isEmpty)
        #expect(firstScene.checklistVisualSuggestionInFlightIDs.isEmpty)
        #expect(secondScene.checklistVisualSuggestionInFlightIDs.isEmpty)
    }

    @Test @MainActor
    func committedLocalTaskArchiveClearsOtherSceneSelectionAndRoute() throws {
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
        #expect(Set(try timeRepository.activeSegments().map(\.id)) == [older.id, newer.id])
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

    @Test @MainActor
    func postCommitSnapshotFailureDoesNotUndoOrThrowForTheCommittedSystemAction() throws {
        try withSystemActionCloudSyncMode {
            let context = try makeTestContext()
            let outcome = try makeTestSystemActionCommandHandler().addInboxItem(
                title: "Committed before snapshot",
                container: context.container,
                deviceID: "test"
            )
            let itemID = try #require(outcome.affectedItemIDs.first)
            let unwritableStateURL = URL(fileURLWithPath: "/dev/null")
                .appendingPathComponent("TimeTrackerState-\(UUID().uuidString).json")
            let error = CommittedMutationSnapshotRecorder(
                syncConflictService: SyncConflictService(stateURL: unwritableStateURL)
            ).recordLocalMutation(
                context: context,
                events: [.inboxChanged(itemIDs: [itemID])]
            )

            #expect(error != nil)
            let persistedItems = try context.fetch(FetchDescriptor<InboxItem>())
            #expect(persistedItems.contains { $0.id == itemID && $0.deletedAt == nil })
        }
    }

    @Test @MainActor
    func committedTimerMutationRefreshesAndClearsClosedAppWidgetState() async throws {
        let context = try makeTestContext()
        let taskRepository = SwiftDataTaskRepository(context: context, deviceID: "test")
        let task = try taskRepository.createTask(
            title: "External timer",
            parentID: nil,
            colorHex: "#0A84FF",
            iconName: "timer"
        )
        let suiteName = "CommittedMutationSurfaceTests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let sharedStore = SharedWidgetSnapshotStore(defaults: defaults)
        let synchronizer = CommittedMutationSurfaceSynchronizer(
            widgetCache: WidgetSnapshotCache(store: sharedStore)
        )
        let events: Set<StoreDomainEvent> = [
            .ledgerChanged(taskID: task.id, dateInterval: nil, isVisible: true),
            .pomodoroChanged(runID: nil, sessionID: nil, taskID: task.id)
        ]

        let segmentID = try #require(
            try makeTestSystemActionCommandHandler().startTimer(
                taskID: task.id,
                context: context
            )
        )
        let runningRefreshError = await synchronizer.synchronize(
            context: context,
            events: events
        )
        #expect(runningRefreshError == nil)
        let runningSnapshot = try #require(sharedStore.load())
        #expect(runningSnapshot.activeTimers.map(\.id) == [segmentID])
        #expect(runningSnapshot.activeTimers.map(\.title) == ["External timer"])

        _ = try makeTestSystemActionCommandHandler().stopTimer(taskID: task.id, context: context)
        let stoppedRefreshError = await synchronizer.synchronize(
            context: context,
            events: events
        )
        #expect(stoppedRefreshError == nil)
        let stoppedSnapshot = try #require(sharedStore.load())
        #expect(stoppedSnapshot.activeTimers.isEmpty)
    }
}

@MainActor
private func withSystemActionCloudSyncMode(_ body: () throws -> Void) throws {
    let defaults = UserDefaults.standard
    let previousMode = defaults.object(forKey: AppCloudSync.modeKey)
    let previousUploadReset = defaults.object(forKey: AppCloudSync.pendingCloudUploadResetKey)
    let previousDownloadReset = defaults.object(forKey: AppCloudSync.pendingCloudDownloadResetKey)
    let previousQueuedReconciliation = defaults.object(forKey: AppCloudSync.queuedCloudReconciliationKey)
    let previousActiveReconciliation = defaults.object(forKey: AppCloudSync.activeCloudReconciliationKey)
    let previousCloudRecoveryStoreReset = defaults.object(forKey: AppCloudSync.cloudRecoveryStoreResetKey)
    let previousActiveCloudDownloadRecovery = defaults.object(forKey: AppCloudSync.activeCloudDownloadRecoveryKey)
    defaults.set(AppCloudSync.modeICloud, forKey: AppCloudSync.modeKey)
    defaults.removeObject(forKey: AppCloudSync.pendingCloudUploadResetKey)
    defaults.removeObject(forKey: AppCloudSync.pendingCloudDownloadResetKey)
    defaults.removeObject(forKey: AppCloudSync.queuedCloudReconciliationKey)
    defaults.removeObject(forKey: AppCloudSync.activeCloudReconciliationKey)
    defaults.removeObject(forKey: AppCloudSync.cloudRecoveryStoreResetKey)
    defaults.removeObject(forKey: AppCloudSync.activeCloudDownloadRecoveryKey)
    defer {
        if let previousMode {
            defaults.set(previousMode, forKey: AppCloudSync.modeKey)
        } else {
            defaults.removeObject(forKey: AppCloudSync.modeKey)
        }
        if let previousUploadReset {
            defaults.set(previousUploadReset, forKey: AppCloudSync.pendingCloudUploadResetKey)
        } else {
            defaults.removeObject(forKey: AppCloudSync.pendingCloudUploadResetKey)
        }
        if let previousDownloadReset {
            defaults.set(previousDownloadReset, forKey: AppCloudSync.pendingCloudDownloadResetKey)
        } else {
            defaults.removeObject(forKey: AppCloudSync.pendingCloudDownloadResetKey)
        }
        if let previousQueuedReconciliation {
            defaults.set(previousQueuedReconciliation, forKey: AppCloudSync.queuedCloudReconciliationKey)
        } else {
            defaults.removeObject(forKey: AppCloudSync.queuedCloudReconciliationKey)
        }
        if let previousActiveReconciliation {
            defaults.set(previousActiveReconciliation, forKey: AppCloudSync.activeCloudReconciliationKey)
        } else {
            defaults.removeObject(forKey: AppCloudSync.activeCloudReconciliationKey)
        }
        if let previousCloudRecoveryStoreReset {
            defaults.set(previousCloudRecoveryStoreReset, forKey: AppCloudSync.cloudRecoveryStoreResetKey)
        } else {
            defaults.removeObject(forKey: AppCloudSync.cloudRecoveryStoreResetKey)
        }
        if let previousActiveCloudDownloadRecovery {
            defaults.set(previousActiveCloudDownloadRecovery, forKey: AppCloudSync.activeCloudDownloadRecoveryKey)
        } else {
            defaults.removeObject(forKey: AppCloudSync.activeCloudDownloadRecoveryKey)
        }
    }
    try body()
}
