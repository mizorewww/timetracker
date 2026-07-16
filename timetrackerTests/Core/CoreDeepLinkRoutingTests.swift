import Foundation
import Testing
@testable import timetracker

@Suite(.serialized)
struct CoreDeepLinkRoutingTests {
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
        #expect(router.action(for: try #require(URL(string: "timetracker://timer/start?taskID=\(taskID.uuidString)"))) == .startTimer(taskID))
        #expect(router.action(for: try #require(URL(string: "timetracker://timer/stop?taskID=\(taskID.uuidString)"))) == .stopTimer(taskID))
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
        #expect(router.action(for: try #require(URL(string: "timetracker://timer/start?other=value"))) == nil)
        #expect(router.action(for: try #require(URL(string: "timetracker://open/inbox/extra"))) == nil)
        #expect(router.action(for: try #require(URL(string: "timetracker://open/inbox#fragment"))) == nil)
    }

    @Test @MainActor
    func pendingDeepLinksAreValidatedDeduplicatedBoundedAndDrained() throws {
        var queue = PendingDeepLinkQueue(capacity: 2)
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

    @Test
    func appAndWidgetDeclareDeepLinkIntegrationPoints() throws {
        let info = try sourceText("timetracker/Info.plist")
        let contentView = try sourceText("timetracker/App/ContentView.swift")
        let widget = try sourceText("timetrackerWidgetExtension/WidgetSupport.swift")

        #expect(info.contains("<string>timetracker</string>"))
        #expect(contentView.contains(".onOpenURL"))
        #expect(contentView.contains("PendingDeepLinkQueue"))
        #expect(contentView.contains("store.handleDeepLink"))
        #expect(widget.contains("timetracker://timer/start"))
        #expect(widget.contains("timetracker://open/today"))
    }

    @Test
    func liveActivityDeclaresStopDeepLinkAndLocalizedAction() throws {
        let router = try sourceText("timetracker/App/AppDeepLinkRouter.swift")
        let activity = try [
            "timetrackerLiveActivityExtension/TimeTrackerLiveActivityBundle.swift",
            "timetrackerLiveActivityExtension/LiveActivityTimerViews.swift",
            "timetrackerLiveActivityExtension/LiveActivitySupport.swift"
        ].map(sourceText).joined(separator: "\n")
        let strings = try sourceText("timetrackerLiveActivityExtension/en.lproj/Localizable.strings")

        #expect(router.contains("case stopTimer(UUID?)"))
        #expect(activity.contains("timetracker://timer/stop?taskID="))
        #expect(activity.contains("live.timer.stop"))
        #expect(strings.contains("\"live.timer.stop\""))
    }

    @Test
    func liveActivityMatchesImmutableTaskAttributesAndExposesAccessibleFreshness() throws {
        let coordinator = try sourceText("timetracker/App/TimeTrackerLiveActivities.swift")
        let activity = try [
            "timetrackerLiveActivityExtension/TimeTrackerLiveActivityBundle.swift",
            "timetrackerLiveActivityExtension/LiveActivityTimerViews.swift",
            "timetrackerLiveActivityExtension/LiveActivitySupport.swift"
        ].map(sourceText).joined(separator: "\n")

        #expect(coordinator.contains("$0.attributes.taskID == request.taskID"))
        #expect(coordinator.contains("LiveActivityTimingPolicy.staleDate(for: request.state.startedAt)"))
        #expect(!coordinator.contains("lastSignature"))
        #expect(activity.contains("context.isStale"))
        #expect(activity.contains(".privacySensitive()"))
        #expect(activity.contains("width: 44, height: 44"))
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
