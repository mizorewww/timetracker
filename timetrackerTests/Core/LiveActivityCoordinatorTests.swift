#if os(iOS) && canImport(ActivityKit)
import ActivityKit
import Foundation
import Synchronization
import Testing
@testable import timetracker

@Suite(.serialized)
@MainActor
struct LiveActivityCoordinatorTests {
    @Test
    func activityKitLifecycleStatesMapWithoutCollapsingVisibility() {
        let cases: [(ActivityState, LiveActivityLifecycleState)] = [
            (.pending, .pending),
            (.active, .active),
            (.stale, .stale),
            (.ended, .ended),
            (.dismissed, .dismissed)
        ]

        for (activityKitState, expected) in cases {
            #expect(LiveActivityLifecycleState(activityKitState) == expected)
        }
    }

    @Test
    func authorizationErrorsMapToActionableFailures() {
        let cases: [(ActivityAuthorizationError, LiveActivityFailure)] = [
            (.attributesTooLarge, .payloadTooLarge),
            (.unsupported, .unsupported),
            (.denied, .denied),
            (.globalMaximumExceeded, .capacity),
            (.targetMaximumExceeded, .capacity),
            (.unsupportedTarget, .configuration),
            (.visibility, .backgroundStart),
            (.persistenceFailure, .system),
            (.missingProcessIdentifier, .configuration),
            (.unentitled, .configuration),
            (.malformedActivityIdentifier, .configuration),
            (.reconnectNotPermitted, .configuration)
        ]

        for (error, expected) in cases {
            #expect(LiveActivityFailure(error) == expected)
        }
        #expect(LiveActivityFailure(UnknownLiveActivityError()) == .system)
    }

    @Test
    func initialStatusReflectsAuthorization() {
        let enabled = LiveActivityCoordinator(
            client: FakeLiveActivitySystemClient(activitiesEnabled: true)
        )
        let disabled = LiveActivityCoordinator(
            client: FakeLiveActivitySystemClient(activitiesEnabled: false)
        )

        #expect(enabled.status == .ready)
        #expect(disabled.status == .unavailable(.denied))
    }

    @Test
    func authorizationRecoveryRetriesTheRetainedTimerExactlyOnce() async {
        let client = FakeLiveActivitySystemClient(activitiesEnabled: false)
        let coordinator = LiveActivityCoordinator(client: client)
        let scenario = makeScenario()

        coordinator.sync(
            activeSegments: [scenario.segment],
            tasks: [scenario.task],
            now: scenario.now
        )
        await coordinator.waitUntilIdle()
        #expect(coordinator.status == .unavailable(.denied))
        #expect(client.requestCount == 0)

        client.setActivitiesEnabled(true)
        #expect(await eventually { client.requestCount == 1 })
        await coordinator.waitUntilIdle()
        #expect(coordinator.status == .active)

        client.setActivitiesEnabled(true)
        for _ in 0..<20 { await Task.yield() }
        #expect(client.requestCount == 1)
    }

    @Test
    func stoppedTimerIsNotResurrectedWhenAuthorizationRecovers() async {
        let scenario = makeScenario()
        let client = FakeLiveActivitySystemClient(
            activitiesEnabled: false,
            activities: [
                LiveActivityRegistration(
                    id: "orphan",
                    segmentID: scenario.segment.id.uuidString
                )
            ]
        )
        let coordinator = LiveActivityCoordinator(client: client)

        coordinator.sync(
            activeSegments: [scenario.segment],
            tasks: [scenario.task],
            now: scenario.now
        )
        await coordinator.waitUntilIdle()
        coordinator.sync(activeSegments: [], tasks: [scenario.task], now: scenario.now)
        await coordinator.waitUntilIdle()

        client.setActivitiesEnabled(true)
        #expect(await eventually { coordinator.status == .ready })
        await coordinator.waitUntilIdle()
        #expect(client.requestCount == 0)
        #expect(client.endCount == 1)
        #expect(client.activities.isEmpty)
    }

    @Test
    func backgroundStartFailureCanRetryWithoutAnotherTimerMutation() async {
        let client = FakeLiveActivitySystemClient(activitiesEnabled: true)
        client.requestError = ActivityAuthorizationError.visibility
        let coordinator = LiveActivityCoordinator(client: client)
        let scenario = makeScenario()

        coordinator.sync(
            activeSegments: [scenario.segment],
            tasks: [scenario.task],
            now: scenario.now
        )
        await coordinator.waitUntilIdle()
        #expect(coordinator.status == .unavailable(.backgroundStart))
        #expect(client.requestCount == 1)

        client.requestError = nil
        coordinator.retryLatestDesiredState()
        await coordinator.waitUntilIdle()
        #expect(client.requestCount == 2)
        #expect(coordinator.status == .active)
    }

    @Test
    func authorizationChangeWinsOverSuspendedUpdateCompletion() async {
        let scenario = makeScenario()
        let registration = LiveActivityRegistration(
            id: "existing",
            segmentID: scenario.segment.id.uuidString
        )
        let client = FakeLiveActivitySystemClient(
            activitiesEnabled: true,
            activities: [registration]
        )
        client.shouldBlockNextUpdate = true
        let coordinator = LiveActivityCoordinator(client: client)

        coordinator.sync(
            activeSegments: [scenario.segment],
            tasks: [scenario.task],
            now: scenario.now
        )
        #expect(await eventually { client.updateCount == 1 })
        client.setActivitiesEnabled(false)
        #expect(await eventually { coordinator.status == .unavailable(.denied) })

        client.releaseBlockedUpdate()
        await coordinator.waitUntilIdle()
        #expect(coordinator.status == .unavailable(.denied))
    }

    @Test
    func matchingFastPathDoesNotOverwriteDisabledStatus() async {
        let scenario = makeScenario()
        let registration = LiveActivityRegistration(
            id: "existing",
            segmentID: scenario.segment.id.uuidString
        )
        let client = FakeLiveActivitySystemClient(
            activitiesEnabled: true,
            activities: [registration]
        )
        let coordinator = LiveActivityCoordinator(client: client)

        coordinator.sync(
            activeSegments: [scenario.segment],
            tasks: [scenario.task],
            now: scenario.now
        )
        await coordinator.waitUntilIdle()
        #expect(coordinator.status == .active)

        client.setActivitiesEnabled(false)
        #expect(await eventually { coordinator.status == .unavailable(.denied) })
        coordinator.sync(
            activeSegments: [scenario.segment],
            tasks: [scenario.task],
            now: scenario.now
        )
        #expect(coordinator.status == .unavailable(.denied))
    }

    @Test
    func authorizationRecoveryDuringSuspendedUpdateReplaysSerially() async {
        let scenario = makeScenario()
        let client = FakeLiveActivitySystemClient(
            activitiesEnabled: true,
            activities: [
                LiveActivityRegistration(
                    id: "existing",
                    segmentID: scenario.segment.id.uuidString
                )
            ]
        )
        client.shouldBlockNextUpdate = true
        let coordinator = LiveActivityCoordinator(client: client)

        coordinator.sync(
            activeSegments: [scenario.segment],
            tasks: [scenario.task],
            now: scenario.now
        )
        #expect(await eventually { client.updateCount == 1 })

        client.setActivitiesEnabled(false)
        client.setActivitiesEnabled(true)
        for _ in 0..<20 { await Task.yield() }
        #expect(client.updateCount == 1)

        client.releaseBlockedUpdate()
        await coordinator.waitUntilIdle()
        #expect(client.updateCount == 2)
        #expect(coordinator.status == .active)
    }

    @Test
    func stopDuringSuspendedUpdateEndsActivityWithoutRecreatingIt() async {
        let scenario = makeScenario()
        let client = FakeLiveActivitySystemClient(
            activitiesEnabled: true,
            activities: [
                LiveActivityRegistration(
                    id: "existing",
                    segmentID: scenario.segment.id.uuidString
                )
            ]
        )
        client.shouldBlockNextUpdate = true
        let coordinator = LiveActivityCoordinator(client: client)

        coordinator.sync(
            activeSegments: [scenario.segment],
            tasks: [scenario.task],
            now: scenario.now
        )
        #expect(await eventually { client.updateCount == 1 })
        coordinator.sync(activeSegments: [], tasks: [scenario.task], now: scenario.now)

        client.releaseBlockedUpdate()
        await coordinator.waitUntilIdle()
        #expect(client.updateCount == 1)
        #expect(client.endCount == 1)
        #expect(client.requestCount == 0)
        #expect(client.activities.isEmpty)
        #expect(coordinator.status == .ready)
    }

    @Test
    func pendingRequestDoesNotReportActiveUntilActivityKitDoes() async {
        let client = FakeLiveActivitySystemClient(activitiesEnabled: true)
        client.requestLifecycleState = .pending
        let coordinator = LiveActivityCoordinator(client: client)
        let scenario = makeScenario()

        coordinator.sync(
            activeSegments: [scenario.segment],
            tasks: [scenario.task],
            now: scenario.now
        )
        await coordinator.waitUntilIdle()

        #expect(client.requestCount == 1)
        #expect(coordinator.status == .synchronizing)
        coordinator.sync(
            activeSegments: [scenario.segment],
            tasks: [scenario.task],
            now: scenario.now
        )
        await coordinator.waitUntilIdle()
        #expect(client.requestCount == 1)
        let activityID = try? #require(client.activities.first?.id)
        #expect(activityID != nil)

        if let activityID {
            client.sendActivityState(.active, for: activityID)
            #expect(await eventually { coordinator.status == .active })
        }
    }

    @Test
    func pendingActivityAppliesTheLatestTaskContentAfterBecomingActive() async {
        let client = FakeLiveActivitySystemClient(activitiesEnabled: true)
        client.requestLifecycleState = .pending
        let coordinator = LiveActivityCoordinator(client: client)
        let scenario = makeScenario()

        coordinator.sync(
            activeSegments: [scenario.segment],
            tasks: [scenario.task],
            now: scenario.now
        )
        await coordinator.waitUntilIdle()
        #expect(client.requestedContents.last?.state.taskTitle == "Live Activity")

        scenario.task.title = "Updated while pending"
        coordinator.sync(
            activeSegments: [scenario.segment],
            tasks: [scenario.task],
            now: scenario.now
        )
        await coordinator.waitUntilIdle()
        #expect(client.updateCount == 0)

        let activityID = try? #require(client.activities.first?.id)
        if let activityID {
            client.sendActivityState(.active, for: activityID)
            #expect(await eventually { client.updateCount == 1 })
            await coordinator.waitUntilIdle()
        }

        #expect(client.updatedContents.last?.state.taskTitle == "Updated while pending")
        #expect(coordinator.status == .active)
    }

    @Test
    func dismissedActivityWaitsForExplicitRetryWhileItsTimerStillRuns() async {
        let scenario = makeScenario()
        let registration = LiveActivityRegistration(
            id: "existing",
            segmentID: scenario.segment.id.uuidString,
            state: .active
        )
        let client = FakeLiveActivitySystemClient(
            activitiesEnabled: true,
            activities: [registration]
        )
        let coordinator = LiveActivityCoordinator(client: client)

        coordinator.sync(
            activeSegments: [scenario.segment],
            tasks: [scenario.task],
            now: scenario.now
        )
        await coordinator.waitUntilIdle()
        #expect(coordinator.status == .active)

        client.sendActivityState(.dismissed, for: registration.id)
        #expect(await eventually {
            coordinator.status == .unavailable(.removed)
        })
        for _ in 0..<20 { await Task.yield() }
        await coordinator.waitUntilIdle()

        #expect(client.requestCount == 0)
        coordinator.retryLatestDesiredState()
        await coordinator.waitUntilIdle()

        #expect(client.requestCount == 1)
        #expect(client.activities.count == 1)
        #expect(client.activities.first?.state == .active)
        #expect(coordinator.status == .active)
    }

    @Test
    func initiallyDismissedRegistrationRequiresExplicitRetry() async {
        let scenario = makeScenario()
        let client = FakeLiveActivitySystemClient(
            activitiesEnabled: true,
            activities: [
                LiveActivityRegistration(
                    id: "dismissed",
                    segmentID: scenario.segment.id.uuidString,
                    state: .dismissed
                )
            ]
        )
        let coordinator = LiveActivityCoordinator(client: client)

        coordinator.sync(
            activeSegments: [scenario.segment],
            tasks: [scenario.task],
            now: scenario.now
        )
        await coordinator.waitUntilIdle()

        #expect(client.requestCount == 0)
        #expect(client.endCount == 0)
        #expect(coordinator.status == .unavailable(.removed))

        coordinator.retryLatestDesiredState()
        await coordinator.waitUntilIdle()
        #expect(client.endCount == 1)
        #expect(client.requestCount == 1)
        #expect(coordinator.status == .active)
    }

    @Test
    func authorizationRecoveryDoesNotOverrideUserRemoval() async {
        let scenario = makeScenario()
        let registration = LiveActivityRegistration(
            id: "existing",
            segmentID: scenario.segment.id.uuidString,
            state: .active
        )
        let client = FakeLiveActivitySystemClient(
            activitiesEnabled: true,
            activities: [registration]
        )
        let coordinator = LiveActivityCoordinator(client: client)

        coordinator.sync(
            activeSegments: [scenario.segment],
            tasks: [scenario.task],
            now: scenario.now
        )
        await coordinator.waitUntilIdle()
        client.sendActivityState(.dismissed, for: registration.id)
        #expect(await eventually {
            coordinator.status == .unavailable(.removed)
        })

        client.setActivitiesEnabled(false)
        #expect(await eventually {
            coordinator.status == .unavailable(.denied)
        })
        client.setActivitiesEnabled(true)
        #expect(await eventually {
            coordinator.status == .unavailable(.removed)
        })
        await coordinator.waitUntilIdle()

        #expect(client.requestCount == 0)
        coordinator.retryLatestDesiredState()
        await coordinator.waitUntilIdle()
        #expect(client.requestCount == 1)
        #expect(coordinator.status == .active)
    }

    @Test
    func dismissalDuringSuspendedUpdateCannotRecreateWithoutExplicitRetry() async {
        let scenario = makeScenario()
        let registration = LiveActivityRegistration(
            id: "existing",
            segmentID: scenario.segment.id.uuidString,
            state: .active
        )
        let client = FakeLiveActivitySystemClient(
            activitiesEnabled: true,
            activities: [registration]
        )
        client.shouldBlockNextUpdate = true
        let coordinator = LiveActivityCoordinator(client: client)

        coordinator.sync(
            activeSegments: [scenario.segment],
            tasks: [scenario.task],
            now: scenario.now
        )
        #expect(await eventually { client.updateCount == 1 })

        client.sendActivityState(.dismissed, for: registration.id)
        client.releaseBlockedUpdate()
        await coordinator.waitUntilIdle()

        #expect(client.requestCount == 0)
        #expect(client.activities.isEmpty)
        #expect(coordinator.status == .unavailable(.removed))

        coordinator.retryLatestDesiredState()
        await coordinator.waitUntilIdle()
        #expect(client.requestCount == 1)
        #expect(coordinator.status == .active)
    }

    @Test
    func systemEndedActivityIsRecreatedWhileItsTimerStillRuns() async {
        let scenario = makeScenario()
        let registration = LiveActivityRegistration(
            id: "existing",
            segmentID: scenario.segment.id.uuidString,
            state: .active
        )
        let client = FakeLiveActivitySystemClient(
            activitiesEnabled: true,
            activities: [registration]
        )
        let coordinator = LiveActivityCoordinator(client: client)

        coordinator.sync(
            activeSegments: [scenario.segment],
            tasks: [scenario.task],
            now: scenario.now
        )
        await coordinator.waitUntilIdle()
        #expect(client.activityStateSubscriptionCount == 1)

        client.sendActivityState(.ended, for: registration.id)
        #expect(await eventually { client.requestCount == 1 })
        await coordinator.waitUntilIdle()

        #expect(client.activities.count == 1)
        #expect(client.activities.first?.state == .active)
        #expect(client.activityStateSubscriptionCount == 2)
        #expect(await eventually { client.activityStateTerminationCount == 1 })
        #expect(coordinator.status == .active)
    }

    @Test
    func staleActivityIsUpdatedAndReturnsToActive() async {
        let scenario = makeScenario()
        let registration = LiveActivityRegistration(
            id: "existing",
            segmentID: scenario.segment.id.uuidString,
            state: .active
        )
        let client = FakeLiveActivitySystemClient(
            activitiesEnabled: true,
            activities: [registration]
        )
        let coordinator = LiveActivityCoordinator(client: client)

        coordinator.sync(
            activeSegments: [scenario.segment],
            tasks: [scenario.task],
            now: scenario.now
        )
        await coordinator.waitUntilIdle()
        #expect(client.updateCount == 1)

        client.sendActivityState(.stale, for: registration.id)
        #expect(await eventually { client.updateCount == 2 })
        await coordinator.waitUntilIdle()

        #expect(client.requestCount == 0)
        #expect(client.activities.first?.state == .active)
        #expect(coordinator.status == .active)
    }

    @Test
    func terminalActivityStateCannotResurrectAStoppedTimer() async {
        let scenario = makeScenario()
        let registration = LiveActivityRegistration(
            id: "existing",
            segmentID: scenario.segment.id.uuidString,
            state: .active
        )
        let client = FakeLiveActivitySystemClient(
            activitiesEnabled: true,
            activities: [registration]
        )
        let coordinator = LiveActivityCoordinator(client: client)

        coordinator.sync(
            activeSegments: [scenario.segment],
            tasks: [scenario.task],
            now: scenario.now
        )
        await coordinator.waitUntilIdle()
        coordinator.sync(activeSegments: [], tasks: [scenario.task], now: scenario.now)
        await coordinator.waitUntilIdle()

        client.sendActivityState(.dismissed, for: registration.id)
        for _ in 0..<20 { await Task.yield() }
        await coordinator.waitUntilIdle()

        #expect(client.requestCount == 0)
        #expect(client.activities.isEmpty)
        #expect(coordinator.status == .ready)
    }

    @Test
    func queuedTerminalStateCannotBeatStopInTheSameSchedulingWindow() async {
        let scenario = makeScenario()
        let registration = LiveActivityRegistration(
            id: "existing",
            segmentID: scenario.segment.id.uuidString,
            state: .active
        )
        let client = FakeLiveActivitySystemClient(
            activitiesEnabled: true,
            activities: [registration]
        )
        let coordinator = LiveActivityCoordinator(client: client)

        coordinator.sync(
            activeSegments: [scenario.segment],
            tasks: [scenario.task],
            now: scenario.now
        )
        await coordinator.waitUntilIdle()

        client.sendActivityState(.ended, for: registration.id)
        coordinator.sync(activeSegments: [], tasks: [scenario.task], now: scenario.now)
        await coordinator.waitUntilIdle()

        #expect(client.requestCount == 0)
        #expect(client.activities.isEmpty)
        #expect(coordinator.status == .ready)
    }

    @Test
    func endedMatchingRegistrationIsReplacedInsteadOfReportedActive() async {
        let scenario = makeScenario()
        let client = FakeLiveActivitySystemClient(
            activitiesEnabled: true,
            activities: [
                LiveActivityRegistration(
                    id: "ended",
                    segmentID: scenario.segment.id.uuidString,
                    state: .ended
                )
            ]
        )
        let coordinator = LiveActivityCoordinator(client: client)

        coordinator.sync(
            activeSegments: [scenario.segment],
            tasks: [scenario.task],
            now: scenario.now
        )
        await coordinator.waitUntilIdle()

        #expect(client.endCount == 1)
        #expect(client.requestCount == 1)
        #expect(client.activities.first?.state == .active)
        #expect(coordinator.status == .active)
    }

    @Test
    func observationSubscriptionIsCancelledWithCoordinator() async {
        let client = FakeLiveActivitySystemClient(activitiesEnabled: true)
        var coordinator: LiveActivityCoordinator? = LiveActivityCoordinator(client: client)

        #expect(coordinator != nil)
        #expect(client.subscriptionCount == 1)
        coordinator = nil

        #expect(await eventually { client.terminationCount == 1 })
    }

    @Test
    func stoppingTimerCancelsActivityStateObservation() async {
        let scenario = makeScenario()
        let client = FakeLiveActivitySystemClient(activitiesEnabled: true)
        let coordinator = LiveActivityCoordinator(client: client)

        coordinator.sync(
            activeSegments: [scenario.segment],
            tasks: [scenario.task],
            now: scenario.now
        )
        await coordinator.waitUntilIdle()
        #expect(client.activityStateSubscriptionCount == 1)

        coordinator.sync(activeSegments: [], tasks: [scenario.task], now: scenario.now)
        await coordinator.waitUntilIdle()

        #expect(await eventually { client.activityStateTerminationCount == 1 })
        #expect(client.activities.isEmpty)
        #expect(coordinator.status == .ready)
    }

    @Test
    func activityStateObservationIsCancelledWithCoordinator() async {
        let scenario = makeScenario()
        let client = FakeLiveActivitySystemClient(activitiesEnabled: true)
        var coordinator: LiveActivityCoordinator? = LiveActivityCoordinator(client: client)

        coordinator?.sync(
            activeSegments: [scenario.segment],
            tasks: [scenario.task],
            now: scenario.now
        )
        await coordinator?.waitUntilIdle()
        #expect(client.activityStateSubscriptionCount == 1)
        coordinator = nil

        #expect(await eventually { client.activityStateTerminationCount == 1 })
    }

    private func makeScenario() -> (task: TaskNode, segment: TimeSegment, now: Date) {
        let now = Date(timeIntervalSinceReferenceDate: 900_000)
        let task = TaskNode(
            title: "Live Activity",
            parentID: nil,
            deviceID: "test"
        )
        let segment = TimeSegment(
            sessionID: UUID(),
            taskID: task.id,
            source: .timer,
            deviceID: "test",
            startedAt: now.addingTimeInterval(-60)
        )
        return (task, segment, now)
    }

    private func eventually(
        _ predicate: @escaping @MainActor () -> Bool
    ) async -> Bool {
        for _ in 0..<1_000 {
            if predicate() { return true }
            await Task.yield()
        }
        return false
    }
}

private struct UnknownLiveActivityError: Error {}

@MainActor
private final class FakeLiveActivitySystemClient: LiveActivitySystemClient {
    private(set) var areActivitiesEnabled: Bool
    private(set) var activities: [LiveActivityRegistration]
    var requestError: Error?
    var requestLifecycleState: LiveActivityLifecycleState = .active
    var updateLifecycleState: LiveActivityLifecycleState? = .active
    var shouldBlockNextUpdate = false

    private(set) var requestCount = 0
    private(set) var updateCount = 0
    private(set) var endCount = 0
    private(set) var subscriptionCount = 0
    private(set) var activityStateSubscriptionCount = 0
    private(set) var requestedContents: [
        ActivityContent<TimeTrackingActivityAttributes.ContentState>
    ] = []
    private(set) var updatedContents: [
        ActivityContent<TimeTrackingActivityAttributes.ContentState>
    ] = []
    private let terminationCounter = LiveActivityTerminationCounter()
    private let activityStateTerminationCounter = LiveActivityTerminationCounter()

    nonisolated var terminationCount: Int {
        terminationCounter.value
    }

    nonisolated var activityStateTerminationCount: Int {
        activityStateTerminationCounter.value
    }

    private var enablementContinuation: AsyncStream<Bool>.Continuation?
    private var activityStateContinuations: [
        String: AsyncStream<LiveActivityLifecycleState>.Continuation
    ] = [:]
    private var terminalRegistrations: [String: LiveActivityRegistration] = [:]
    private var blockedUpdateContinuation: CheckedContinuation<Void, Never>?

    init(
        activitiesEnabled: Bool,
        activities: [LiveActivityRegistration] = []
    ) {
        areActivitiesEnabled = activitiesEnabled
        self.activities = activities
    }

    func activityEnablementUpdates() -> AsyncStream<Bool> {
        subscriptionCount += 1
        let terminationCounter = terminationCounter
        return AsyncStream { continuation in
            enablementContinuation = continuation
            continuation.onTermination = { @Sendable _ in
                terminationCounter.increment()
            }
        }
    }

    func activityStateUpdates(
        for activityID: String
    ) -> AsyncStream<LiveActivityLifecycleState> {
        activityStateSubscriptionCount += 1
        let terminationCounter = activityStateTerminationCounter
        let initial = activities.first { $0.id == activityID }?.state
        return AsyncStream(bufferingPolicy: .bufferingNewest(1)) { continuation in
            if let initial {
                continuation.yield(initial)
            }
            activityStateContinuations[activityID] = continuation
            continuation.onTermination = { @Sendable _ in
                terminationCounter.increment()
            }
        }
    }

    func request(
        attributes: TimeTrackingActivityAttributes,
        content: ActivityContent<TimeTrackingActivityAttributes.ContentState>
    ) throws -> LiveActivityRegistration {
        requestCount += 1
        requestedContents.append(content)
        if let requestError { throw requestError }
        let registration = LiveActivityRegistration(
            id: "activity-\(requestCount)",
            segmentID: attributes.segmentID,
            state: requestLifecycleState
        )
        activities.append(registration)
        return registration
    }

    func update(
        activityID: String,
        content: ActivityContent<TimeTrackingActivityAttributes.ContentState>
    ) async -> LiveActivityRegistration? {
        updateCount += 1
        updatedContents.append(content)
        if shouldBlockNextUpdate {
            shouldBlockNextUpdate = false
            await withCheckedContinuation { continuation in
                blockedUpdateContinuation = continuation
            }
        }
        guard let index = activities.firstIndex(where: { $0.id == activityID }) else {
            return terminalRegistrations[activityID]
        }
        if let updateLifecycleState {
            activities[index] = LiveActivityRegistration(
                id: activities[index].id,
                segmentID: activities[index].segmentID,
                state: updateLifecycleState
            )
        }
        return activities[index]
    }

    func end(
        activityID: String,
        content: ActivityContent<TimeTrackingActivityAttributes.ContentState>
    ) async {
        endCount += 1
        activities.removeAll { $0.id == activityID }
    }

    func sendActivityState(
        _ state: LiveActivityLifecycleState,
        for activityID: String
    ) {
        if state.isTerminal {
            if let registration = activities.first(where: { $0.id == activityID }) {
                terminalRegistrations[activityID] = LiveActivityRegistration(
                    id: registration.id,
                    segmentID: registration.segmentID,
                    state: state
                )
            }
            activities.removeAll { $0.id == activityID }
        } else if let index = activities.firstIndex(where: { $0.id == activityID }) {
            activities[index] = LiveActivityRegistration(
                id: activities[index].id,
                segmentID: activities[index].segmentID,
                state: state
            )
        }
        activityStateContinuations[activityID]?.yield(state)
    }

    func setActivitiesEnabled(_ enabled: Bool) {
        areActivitiesEnabled = enabled
        enablementContinuation?.yield(enabled)
    }

    func releaseBlockedUpdate() {
        blockedUpdateContinuation?.resume()
        blockedUpdateContinuation = nil
    }
}

private final class LiveActivityTerminationCounter: Sendable {
    private let storage = Mutex(0)

    var value: Int {
        storage.withLock { $0 }
    }

    func increment() {
        storage.withLock { $0 += 1 }
    }
}
#endif
