import Foundation
import SwiftData
import Testing
@testable import timetracker

@Suite(.serialized)
struct CoreDeepLinkRoutingTests {
    @Test
    func liveActivityProjectionBoundsPreserveUnicodeAndPayloadHeadroom() {
        let source = String(repeating: "任务🧠/Focus", count: 256)
        let bounded = LiveActivityProjectionLimits.boundedUTF8Prefix(
            source,
            maximumUTF8Bytes: LiveActivityProjectionLimits.maximumTitleUTF8Bytes
        )

        #expect(bounded.utf8.count <= LiveActivityProjectionLimits.maximumTitleUTF8Bytes)
        #expect(source.hasPrefix(bounded))
        #expect(bounded.contains("\u{FFFD}") == false)
        #expect(
            LiveActivityProjectionLimits.maximumTitleUTF8Bytes
                + LiveActivityProjectionLimits.maximumPathUTF8Bytes * 2
                + LiveActivityProjectionLimits.maximumIconUTF8Bytes
                + LiveActivityProjectionLimits.maximumColorUTF8Bytes
                < 3_072
        )
    }

    @Test
    func liveActivityProjectionReusesTaskIdentityBreadcrumbAndVisual() {
        let root = TaskNode(
            title: "Client",
            parentID: nil,
            deviceID: "test",
            colorHex: "1677FF",
            iconName: "folder"
        )
        let child = TaskNode(
            title: "Review",
            parentID: root.id,
            deviceID: "test",
            colorHex: "34C759",
            iconName: "checkmark.circle"
        )

        let projection = LiveActivityProjectionService().taskProjection(
            taskID: child.id,
            tasks: [child, root],
            fallbackTitle: "Fallback"
        )

        #expect(projection.title == "Review")
        #expect(projection.path == "/Client/Review")
        #expect(projection.abbreviatedPath == "/C/R")
        #expect(projection.iconName == "checkmark.circle")
        #expect(projection.colorHex == "34C759")
    }

    @Test
    func liveActivityPrimarySelectionIsStableAndRejectsUnusableSegments() throws {
        let taskID = UUID()
        let startedAt = Date(timeIntervalSinceReferenceDate: 50_000)
        let lowerID = try #require(UUID(uuidString: "00000000-0000-0000-0000-000000000001"))
        let higherID = try #require(UUID(uuidString: "00000000-0000-0000-0000-000000000002"))
        let higher = TimeSegment(
            sessionID: UUID(),
            taskID: taskID,
            source: .timer,
            deviceID: "test",
            startedAt: startedAt
        )
        higher.id = higherID
        let lower = TimeSegment(
            sessionID: UUID(),
            taskID: taskID,
            source: .timer,
            deviceID: "test",
            startedAt: startedAt
        )
        lower.id = lowerID
        let deleted = TimeSegment(
            sessionID: UUID(),
            taskID: taskID,
            source: .timer,
            deviceID: "test",
            startedAt: startedAt.addingTimeInterval(-60)
        )
        deleted.deletedAt = startedAt
        let future = TimeSegment(
            sessionID: UUID(),
            taskID: taskID,
            source: .timer,
            deviceID: "test",
            startedAt: startedAt.addingTimeInterval(60)
        )

        let selected = LiveActivityProjectionService().primarySegment(
            from: [future, higher, deleted, lower],
            now: startedAt
        )

        #expect(selected?.id == lowerID)
    }

    @Test
    func liveActivityTimingPolicyFreezesElapsedTimeAtItsStaleBoundary() {
        let startedAt = Date(timeIntervalSinceReferenceDate: 10_000)

        #expect(
            LiveActivityTimingPolicy.staleDate(for: startedAt)
                == startedAt.addingTimeInterval(8 * 60 * 60)
        )
        #expect(
            LiveActivityTimingPolicy.elapsedPresentation(
                startedAt: startedAt,
                isStale: false
            ) == .live(startedAt: startedAt)
        )
        #expect(
            LiveActivityTimingPolicy.elapsedPresentation(
                startedAt: startedAt,
                isStale: true
            ) == .frozen(seconds: 8 * 60 * 60)
        )
    }

    @Test @MainActor
    func timerDeepLinksResolveFreshStoreStateInsteadOfFacadeCaches() throws {
        let context = try makeTestContext()
        let store = makeTestStore()
        store.configureRepositoriesIfNeeded(context: context)
        #expect(store.tasks.isEmpty)
        #expect(store.activeSegments.isEmpty)

        let writerContext = ModelContext(context.container)
        let task = try SwiftDataTaskRepository(
            context: writerContext,
            deviceID: "external"
        ).createTask(
            title: "Arrived after scene refresh",
            parentID: nil,
            colorHex: nil,
            iconName: nil
        )
        let startURL = try #require(
            URL(string: "timetracker://timer/start?taskID=\(task.id.uuidString)")
        )
        let presentationRouter = AppPresentationRouter()

        #expect(
            store.handleDeepLink(startURL, presentationRouter: presentationRouter)
                == .handled
        )
        let activeSegment = try #require(store.activeSegments.first)
        #expect(activeSegment.taskID == task.id)
        #expect(store.task(for: task.id)?.title == task.title)

        // Make the scene cache stale again, then require the exact stop to be
        // resolved from the store-scoped fresh context.
        store.activeSegments = []
        let stopURL = try #require(
            URL(
                string: "timetracker://timer/stop?segmentID=\(activeSegment.id.uuidString)"
            )
        )
        #expect(
            store.handleDeepLink(stopURL, presentationRouter: presentationRouter)
                == .handled
        )
        #expect(store.activeSegments.isEmpty)
        #expect(
            try SwiftDataTimeTrackingRepository(
                context: ModelContext(context.container),
                deviceID: "test"
            ).activeSegments().isEmpty
        )
    }

    @Test @MainActor
    func widgetStartDeepLinkPersistsItsSystemSurfaceSource() throws {
        let context = try makeTestContext()
        let task = try SwiftDataTaskRepository(
            context: context,
            deviceID: "test"
        ).createTask(
            title: "Widget task",
            parentID: nil,
            colorHex: nil,
            iconName: nil
        )
        let store = makeTestStore()
        store.configureIfNeeded(context: context)
        let url = try #require(
            URL(
                string: "timetracker://timer/start?taskID=\(task.id.uuidString)&source=widget"
            )
        )

        #expect(
            store.handleDeepLink(url, presentationRouter: AppPresentationRouter())
                == .handled
        )
        let persistedSegment = try #require(
            SwiftDataTimeTrackingRepository(
                context: ModelContext(context.container),
                deviceID: "test"
            ).allSegments().first
        )
        #expect(persistedSegment.source == .widget)
    }

    @Test @MainActor
    func latestDesiredStateReconcilerSerializesAndCoalescesStopStartTransitions() async {
        let probe = LiveActivityReconciliationProbe()
        let reconciler = LatestDesiredStateReconciler<String> { state in
            await probe.reconcile(state)
        }

        reconciler.submit("stopped")
        while probe.isStopBlocked == false {
            await Task.yield()
        }

        reconciler.submit("stopped")
        reconciler.submit("started-a")
        reconciler.submit("started-b")

        #expect(probe.events == ["begin:stopped"])
        #expect(probe.maximumConcurrentOperations == 1)
        probe.releaseStop()
        await reconciler.waitUntilIdle()

        #expect(
            probe.events == [
                "begin:stopped",
                "end:stopped",
                "begin:started-b",
                "end:started-b"
            ]
        )
        #expect(probe.maximumConcurrentOperations == 1)
        #expect(reconciler.desiredState == "started-b")
        #expect(reconciler.isReconciling == false)
    }

    @Test @MainActor
    func deepLinkRouterMapsKnownWidgetRoutesToAppActions() throws {
        let router = AppDeepLinkRouter()

        #expect(router.action(for: try #require(URL(string: "timetracker://open/inbox"))) == .open(.inbox))
        #expect(router.action(for: try #require(URL(string: "timetracker://open/tasks"))) == .open(.tasks))
        #expect(router.action(for: try #require(URL(string: "timetracker://timer/start"))) == .startTimerPicker)
        let taskID = UUID()
        #expect(router.action(for: try #require(URL(string: "timetracker://timer/start?taskID=\(taskID.uuidString)"))) == .startTimer(taskID, source: .timer))
        #expect(router.action(for: try #require(URL(string: "timetracker://timer/start?taskID=\(taskID.uuidString)&source=widget"))) == .startTimer(taskID, source: .widget))
        #expect(router.action(for: try #require(URL(string: "timetracker://timer/stop?taskID=\(taskID.uuidString)"))) == .stopTimer(.task(taskID)))
        let segmentID = UUID()
        #expect(router.action(for: try #require(URL(string: "timetracker://timer/stop?segmentID=\(segmentID.uuidString)"))) == .stopTimer(.segment(segmentID)))
        #expect(router.action(for: try #require(URL(string: "timetracker://timer/stop"))) == .stopTimer(nil))
        #expect(router.action(for: try #require(URL(string: "timetracker://task/new"))) == .newTask)
        #expect(router.action(for: try #require(URL(string: "timetracker://task/\(taskID.uuidString)"))) == .openTask(taskID))
    }

    @Test @MainActor
    func deepLinkRouterRejectsUnknownOrExternalRoutes() throws {
        let router = AppDeepLinkRouter()

        #expect(router.action(for: try #require(URL(string: "https://example.com/open/inbox"))) == nil)
        #expect(router.action(for: try #require(URL(string: "timetracker://open/missing"))) == nil)
        #expect(router.action(for: try #require(URL(string: "timetracker://timer/missing"))) == nil)
        #expect(router.action(for: try #require(URL(string: "timetracker://task/not-a-uuid"))) == nil)
        #expect(router.action(for: try #require(URL(string: "timetracker://timer/stop?taskID=invalid"))) == nil)
        #expect(router.action(for: try #require(URL(string: "timetracker://timer/stop?segmentID=invalid"))) == nil)
        #expect(router.action(for: try #require(URL(string: "timetracker://timer/stop?taskID=\(UUID())&segmentID=\(UUID())"))) == nil)
        #expect(router.action(for: try #require(URL(string: "timetracker://timer/start?other=value"))) == nil)
        #expect(router.action(for: try #require(URL(string: "timetracker://timer/start?taskID=\(UUID())&source=shortcut"))) == nil)
        #expect(router.action(for: try #require(URL(string: "timetracker://timer/start?taskID=\(UUID())&source=widget&source=widget"))) == nil)
        #expect(router.action(for: try #require(URL(string: "timetracker://open/inbox/extra"))) == nil)
        #expect(router.action(for: try #require(URL(string: "timetracker://open/inbox#fragment"))) == nil)
    }

    @Test @MainActor
    func targetedStopDeepLinkDoesNotStopAnUnrelatedActiveTimer() throws {
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
        let store = makeTestStore()
        store.configureIfNeeded(context: context)
        let url = try #require(
            URL(string: "timetracker://timer/stop?taskID=\(staleTarget.id.uuidString)")
        )

        #expect(
            store.handleDeepLink(url, presentationRouter: AppPresentationRouter())
                == .rejected
        )

        #expect(store.activeSegments.map(\.id) == [runningSegment.id])
        #expect(try timeRepository.activeSegments().map(\.id) == [runningSegment.id])
    }

    @Test @MainActor
    func untargetedStopDeepLinkRejectsParallelTimers() throws {
        let context = try makeTestContext()
        let taskRepository = SwiftDataTaskRepository(context: context, deviceID: "test")
        let timeRepository = SwiftDataTimeTrackingRepository(context: context, deviceID: "test")
        let firstTask = try taskRepository.createTask(title: "First", parentID: nil, colorHex: nil, iconName: nil)
        let secondTask = try taskRepository.createTask(title: "Second", parentID: nil, colorHex: nil, iconName: nil)
        let first = try timeRepository.startTask(taskID: firstTask.id, source: .timer)
        let second = try timeRepository.startTask(taskID: secondTask.id, source: .timer)
        let store = makeTestStore()
        store.configureIfNeeded(context: context)
        let url = try #require(URL(string: "timetracker://timer/stop"))

        #expect(store.handleDeepLink(url, presentationRouter: AppPresentationRouter()) == .rejected)
        #expect(Set(store.activeSegments.map(\.id)) == [first.id, second.id])
        #expect(Set(try timeRepository.activeSegments().map(\.id)) == [first.id, second.id])
    }

    @Test @MainActor
    func untargetedStopDeepLinkRemainsCompatibleForOneTimer() throws {
        let context = try makeTestContext()
        let taskRepository = SwiftDataTaskRepository(context: context, deviceID: "test")
        let timeRepository = SwiftDataTimeTrackingRepository(context: context, deviceID: "test")
        let task = try taskRepository.createTask(title: "Only", parentID: nil, colorHex: nil, iconName: nil)
        _ = try timeRepository.startTask(taskID: task.id, source: .timer)
        let store = makeTestStore()
        store.configureIfNeeded(context: context)
        let url = try #require(URL(string: "timetracker://timer/stop"))

        #expect(store.handleDeepLink(url, presentationRouter: AppPresentationRouter()) == .handled)
        #expect(store.activeSegments.isEmpty)
        #expect(try timeRepository.activeSegments().isEmpty)
    }

    @Test @MainActor
    func segmentStopDeepLinkStopsOnlyItsSerializedParallelTimer() throws {
        let context = try makeTestContext()
        let taskRepository = SwiftDataTaskRepository(context: context, deviceID: "test")
        let timeRepository = SwiftDataTimeTrackingRepository(context: context, deviceID: "test")
        let firstTask = try taskRepository.createTask(title: "First", parentID: nil, colorHex: nil, iconName: nil)
        let secondTask = try taskRepository.createTask(title: "Second", parentID: nil, colorHex: nil, iconName: nil)
        let first = try timeRepository.startTask(taskID: firstTask.id, source: .timer)
        let second = try timeRepository.startTask(taskID: secondTask.id, source: .timer)
        let store = makeTestStore()
        store.configureIfNeeded(context: context)
        let url = try #require(
            URL(string: "timetracker://timer/stop?segmentID=\(first.id.uuidString)")
        )

        #expect(store.handleDeepLink(url, presentationRouter: AppPresentationRouter()) == .handled)
        #expect(store.activeSegments.map(\.id) == [second.id])
        #expect(try timeRepository.activeSegments().map(\.id) == [second.id])
    }

    @Test @MainActor
    func destinationDeepLinksCloseTaskDetailWithoutChangingTimerSelection() throws {
        let context = try makeTestContext()
        let repository = SwiftDataTaskRepository(context: context, deviceID: "test")
        let task = try repository.createTask(
            title: "Deep-link selection",
            parentID: nil,
            colorHex: nil,
            iconName: nil
        )
        let store = makeTestStore()
        store.configureIfNeeded(context: context)
        let todayURL = try #require(URL(string: "timetracker://open/today"))
        let tasksURL = try #require(URL(string: "timetracker://open/tasks"))

        store.openTaskDetail(task.id)
        let presentationRouter = AppPresentationRouter()
        #expect(
            store.handleDeepLink(todayURL, presentationRouter: presentationRouter)
                == .handled
        )

        #expect(store.tasksRoute == nil)
        #expect(store.selectedTaskID == task.id)
        #expect(store.desktopDestination == .today)

        store.openTaskDetail(task.id)
        #expect(
            store.handleDeepLink(tasksURL, presentationRouter: presentationRouter)
                == .handled
        )

        #expect(store.tasksRoute == nil)
        #expect(store.selectedTaskID == task.id)
        #expect(store.desktopDestination == .tasks)
    }

    @Test @MainActor
    func pendingDeepLinksAreValidatedDeduplicatedBoundedAndDrained() throws {
        let queue = PendingDeepLinkQueue(capacity: 2)
        let inbox = try #require(URL(string: "timetracker://open/inbox"))
        let duplicateInbox = try #require(URL(string: "TIMETRACKER://OPEN/inbox"))
        let tasks = try #require(URL(string: "timetracker://open/tasks"))
        let analytics = try #require(URL(string: "timetracker://open/analytics"))
        let external = try #require(URL(string: "https://example.com/open/inbox"))

        let enqueuedInbox = queue.enqueue(inbox)
        #expect(enqueuedInbox)
        let enqueuedDuplicate = queue.enqueue(duplicateInbox)
        #expect(enqueuedDuplicate)
        #expect(queue.urls.count == 1)
        let enqueuedExternal = queue.enqueue(external)
        #expect(!enqueuedExternal)
        let enqueuedTasks = queue.enqueue(tasks)
        #expect(enqueuedTasks)
        let enqueuedAnalytics = queue.enqueue(analytics)
        #expect(enqueuedAnalytics)
        #expect(queue.urls == [tasks, analytics])
        let drainedURLs = queue.drain()
        #expect(drainedURLs == [tasks, analytics])
        #expect(queue.urls.isEmpty)
    }

    @Test @MainActor
    func dirtyWorkspaceKeepsADeferredDeepLinkBatchUntilNavigationCompletes() throws {
        let store = makeTestStore()
        let registrationID = UUID()
        var isDirty = true
        var didRequestConfirmation = false
        var didDismissDetail = false
        store.taskDetailNavigationGuard.register(
            id: registrationID,
            taskID: UUID(),
            hasUnsavedChanges: { isDirty },
            requestDiscardConfirmation: { _ in didRequestConfirmation = true },
            dismissDetail: { didDismissDetail = true }
        )

        let queue = PendingDeepLinkQueue()
        let inbox = try #require(URL(string: "timetracker://open/inbox"))
        let analytics = try #require(URL(string: "timetracker://open/analytics"))
        #expect(queue.enqueue(inbox))
        #expect(queue.enqueue(analytics))
        let coordinator = AppSceneDeepLinkCoordinator(
            store: store,
            presentationRouter: AppPresentationRouter(),
            pendingDeepLinks: queue
        )

        coordinator.drain()
        #expect(didRequestConfirmation)
        #expect(didDismissDetail == false)
        #expect(queue.urls.isEmpty)

        store.taskDetailNavigationGuard.cancelPendingNavigation(id: registrationID)
        #expect(queue.urls.isEmpty)

        #expect(queue.enqueue(inbox))
        #expect(queue.enqueue(analytics))
        coordinator.drain()
        isDirty = false
        store.taskDetailNavigationGuard.completePendingNavigation(id: registrationID)
        #expect(didDismissDetail)
        #expect(store.desktopDestination == .analytics)
        #expect(queue.urls.isEmpty)
    }

    @Test @MainActor
    func rejectedDeepLinkDoesNotAskADirtyWorkspaceToDiscard() throws {
        let store = makeTestStore()
        let registrationID = UUID()
        var didRequestConfirmation = false
        store.taskDetailNavigationGuard.register(
            id: registrationID,
            taskID: UUID(),
            hasUnsavedChanges: { true },
            requestDiscardConfirmation: { _ in didRequestConfirmation = true },
            dismissDetail: {}
        )
        let queue = PendingDeepLinkQueue()
        let missingTask = try #require(
            URL(string: "timetracker://task/\(UUID().uuidString)")
        )
        #expect(queue.enqueue(missingTask))

        AppSceneDeepLinkCoordinator(
            store: store,
            presentationRouter: AppPresentationRouter(),
            pendingDeepLinks: queue
        ).drain()

        #expect(didRequestConfirmation == false)
        #expect(store.taskDetailNavigationGuard.hasPendingNavigation == false)
        #expect(queue.urls.isEmpty)
    }

    @Test @MainActor
    func presentationDeepLinksUseOnlyTheReceivingSceneRouter() throws {
        let store = makeTestStore()
        let receivingScene = AppPresentationRouter()
        let otherScene = AppPresentationRouter()
        let url = try #require(URL(string: "timetracker://timer/start"))

        #expect(
            store.handleDeepLink(url, presentationRouter: receivingScene)
                == .handled
        )

        guard case .startTaskPicker = try #require(receivingScene.sheet).content else {
            Issue.record("The receiving scene did not present the task picker.")
            return
        }
        #expect(otherScene.sheet == nil)
        #expect(store.desktopDestination == .today)
    }

    @Test @MainActor
    func repeatedPresentationDeepLinkIsDeferredWithoutRecreatingTheSheet() throws {
        let store = makeTestStore()
        let presentationRouter = AppPresentationRouter()
        let url = try #require(URL(string: "timetracker://timer/start"))

        #expect(
            store.handleDeepLink(url, presentationRouter: presentationRouter)
                == .handled
        )
        let firstID = try #require(presentationRouter.sheet?.id)
        #expect(
            store.handleDeepLink(url, presentationRouter: presentationRouter)
                == .deferred
        )

        #expect(presentationRouter.sheet?.id == firstID)
        guard case .startTaskPicker = try #require(presentationRouter.sheet).content else {
            Issue.record("A duplicate deep link replaced the current sheet.")
            return
        }
    }

    @Test @MainActor
    func busySceneDefersNewTaskDeepLinkWithoutClosingItsCurrentPresentation() throws {
        let store = makeTestStore()
        store.desktopDestination = .analytics
        let presentationRouter = AppPresentationRouter()
        #expect(presentationRouter.presentStartTaskPicker())
        let pickerID = try #require(presentationRouter.sheet?.id)
        let url = try #require(URL(string: "timetracker://task/new"))

        #expect(
            store.handleDeepLink(url, presentationRouter: presentationRouter)
                == .deferred
        )

        #expect(presentationRouter.sheet?.id == pickerID)
        guard case .startTaskPicker = try #require(presentationRouter.sheet).content else {
            Issue.record("The deep link displaced the busy scene's sheet.")
            return
        }
        #expect(store.desktopDestination == .analytics)
    }

    @Test @MainActor
    func unavailableTimerDeepLinkPreservesPresentationAndDestination() throws {
        let store = makeTestStore()
        store.desktopDestination = .analytics
        let presentationRouter = AppPresentationRouter()
        #expect(presentationRouter.presentQuickStartEditor(using: store))
        let presentationID = try #require(presentationRouter.sheet?.id)
        let url = try #require(
            URL(string: "timetracker://timer/start?taskID=\(UUID().uuidString)")
        )

        #expect(
            store.handleDeepLink(url, presentationRouter: presentationRouter)
                == .rejected
        )

        #expect(store.desktopDestination == .analytics)
        #expect(presentationRouter.sheet?.id == presentationID)
    }

    @Test @MainActor
    func directTimerDeepLinksRunWhileAPresentationIsActive() throws {
        let context = try makeTestContext()
        let repository = SwiftDataTaskRepository(context: context, deviceID: "test")
        let task = try repository.createTask(
            title: "Direct timer",
            parentID: nil,
            colorHex: nil,
            iconName: nil
        )
        let store = makeTestStore()
        store.configureIfNeeded(context: context)
        let presentationRouter = AppPresentationRouter()
        #expect(presentationRouter.presentQuickStartEditor(using: store))
        let presentationID = try #require(presentationRouter.sheet?.id)
        let startURL = try #require(
            URL(string: "timetracker://timer/start?taskID=\(task.id.uuidString)")
        )
        let stopURL = try #require(
            URL(string: "timetracker://timer/stop?taskID=\(task.id.uuidString)")
        )

        #expect(
            store.handleDeepLink(startURL, presentationRouter: presentationRouter)
                == .handled
        )
        #expect(store.activeSegment(for: task.id) != nil)
        #expect(presentationRouter.sheet?.id == presentationID)

        #expect(
            store.handleDeepLink(stopURL, presentationRouter: presentationRouter)
                == .handled
        )
        #expect(store.activeSegment(for: task.id) == nil)
        #expect(presentationRouter.sheet?.id == presentationID)
    }

    @Test @MainActor
    func deferredDeepLinksRemainQueuedUntilTheCurrentPresentationDismisses() throws {
        let store = makeTestStore()
        let presentationRouter = AppPresentationRouter()
        let queue = PendingDeepLinkQueue()
        let newTask = try #require(URL(string: "timetracker://task/new"))
        let startPicker = try #require(URL(string: "timetracker://timer/start"))
        let enqueuedNewTask = queue.enqueue(newTask)
        let enqueuedStartPicker = queue.enqueue(startPicker)
        #expect(enqueuedNewTask)
        #expect(enqueuedStartPicker)

        for url in queue.drain() {
            if store.handleDeepLink(url, presentationRouter: presentationRouter) == .deferred {
                let requeued = queue.enqueue(url)
                #expect(requeued)
            }
        }

        guard case .taskEditor = try #require(presentationRouter.sheet).content else {
            Issue.record("The first queued presentation was not handled.")
            return
        }
        #expect(queue.urls == [startPicker])
        let firstID = try #require(presentationRouter.sheet?.id)
        presentationRouter.dismiss(presentationID: firstID)

        for url in queue.drain() {
            if store.handleDeepLink(url, presentationRouter: presentationRouter) == .deferred {
                let requeued = queue.enqueue(url)
                #expect(requeued)
            }
        }

        guard case .startTaskPicker = try #require(presentationRouter.sheet).content else {
            Issue.record("The deferred presentation did not resume after dismissal.")
            return
        }
        #expect(queue.urls.isEmpty)
    }

    @Test
    func appAndWidgetDeclareDeepLinkIntegrationPoints() throws {
        let info = try sourceText("timetracker/Info.plist")
        let contentView = try sourceText("timetracker/App/ContentView.swift")
        let sceneCoordinator = try sourceText(
            "timetracker/App/AppSceneDeepLinkCoordinator.swift"
        )
        let widget = try sourceText("timetrackerWidgetExtension/WidgetSupport.swift")

        #expect(info.contains("<string>timetracker</string>"))
        #expect(contentView.contains(".onOpenURL"))
        #expect(contentView.contains("PendingDeepLinkQueue"))
        #expect(contentView.contains("AppSceneDeepLinkCoordinator"))
        #expect(sceneCoordinator.contains("store.handleDeepLink"))
        #expect(sceneCoordinator.contains("routesAfterSystemAction: false"))
        #expect(widget.contains("timetracker://timer/start"))
        #expect(widget.contains("source=widget"))
        #expect(widget.contains("timetracker://open/today"))
    }

    @Test
    func liveActivityOnlyOpensTodayAndLeavesStoppingToTheApp() throws {
        let router = try sourceText("timetracker/App/AppDeepLinkRouter.swift")
        let activity = try [
            "timetrackerLiveActivityExtension/TimeTrackerLiveActivityBundle.swift",
            "timetrackerLiveActivityExtension/LiveActivityTimerViews.swift",
            "timetrackerLiveActivityExtension/ExpandedActivityDetails.swift",
            "timetrackerLiveActivityExtension/LiveActivitySupport.swift"
        ].map(sourceText).joined(separator: "\n")
        let strings = try sourceText("timetrackerLiveActivityExtension/en.lproj/Localizable.strings")

        #expect(router.contains("case stopTimer(AppDeepLinkStopTarget?)"))
        #expect(activity.contains("static let today = URL(string: \"timetracker://open/today\")!"))
        #expect(activity.contains(".widgetURL(LiveActivityDeepLinks.today)"))
        #expect(activity.contains("timetracker://timer/stop") == false)
        #expect(activity.contains("Button(intent:") == false)
        #expect(activity.contains("LiveActivityStopTimerIntent") == false)
        #expect(strings.contains("\"live.timer.openToStop\"") == false)
    }

    @Test
    func liveActivityMatchesImmutableTaskAttributesAndExposesAccessibleFreshness() throws {
        let coordinator = try sourceText("timetracker/App/TimeTrackerLiveActivities.swift")
        let activity = try [
            "timetrackerLiveActivityExtension/TimeTrackerLiveActivityBundle.swift",
            "timetrackerLiveActivityExtension/LiveActivityTimerViews.swift",
            "timetrackerLiveActivityExtension/LiveActivitySupport.swift"
        ].map(sourceText).joined(separator: "\n")

        #expect(coordinator.contains("$0.attributes.segmentID == request.segmentID"))
        #expect(coordinator.contains("LiveActivityTimingPolicy.staleDate(for: request.state.startedAt)"))
        #expect(!coordinator.contains("lastSignature"))
        #expect(activity.contains("context.isStale"))
        #expect(activity.contains("LiveActivityTimerRow("))
        #expect(activity.contains("state.taskTitle"))
        #expect(activity.contains(".privacySensitive()"))
        #expect(activity.contains("ActivityIconView(state:"))
        #expect(activity.contains(".widgetURL(LiveActivityDeepLinks.today)"))
    }
}

@MainActor
private final class LiveActivityReconciliationProbe {
    private var stopContinuation: CheckedContinuation<Void, Never>?
    private var activeOperationCount = 0
    private(set) var maximumConcurrentOperations = 0
    private(set) var events: [String] = []

    var isStopBlocked: Bool {
        stopContinuation != nil
    }

    func reconcile(_ state: String) async {
        activeOperationCount += 1
        maximumConcurrentOperations = max(maximumConcurrentOperations, activeOperationCount)
        events.append("begin:\(state)")
        if state == "stopped" {
            await withCheckedContinuation { continuation in
                stopContinuation = continuation
            }
        }
        events.append("end:\(state)")
        activeOperationCount -= 1
    }

    func releaseStop() {
        let continuation = stopContinuation
        stopContinuation = nil
        continuation?.resume()
    }
}
