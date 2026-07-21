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
    func observationSubscriptionIsCancelledWithCoordinator() async {
        let client = FakeLiveActivitySystemClient(activitiesEnabled: true)
        var coordinator: LiveActivityCoordinator? = LiveActivityCoordinator(client: client)

        #expect(coordinator != nil)
        #expect(client.subscriptionCount == 1)
        coordinator = nil

        #expect(await eventually { client.terminationCount == 1 })
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
    var shouldBlockNextUpdate = false

    private(set) var requestCount = 0
    private(set) var updateCount = 0
    private(set) var endCount = 0
    private(set) var subscriptionCount = 0
    private let terminationCounter = LiveActivityTerminationCounter()

    nonisolated var terminationCount: Int {
        terminationCounter.value
    }

    private var enablementContinuation: AsyncStream<Bool>.Continuation?
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

    func request(
        attributes: TimeTrackingActivityAttributes,
        content: ActivityContent<TimeTrackingActivityAttributes.ContentState>
    ) throws -> LiveActivityRegistration {
        requestCount += 1
        if let requestError { throw requestError }
        let registration = LiveActivityRegistration(
            id: "activity-\(requestCount)",
            segmentID: attributes.segmentID
        )
        activities.append(registration)
        return registration
    }

    func update(
        activityID: String,
        content: ActivityContent<TimeTrackingActivityAttributes.ContentState>
    ) async {
        updateCount += 1
        guard shouldBlockNextUpdate else { return }
        shouldBlockNextUpdate = false
        await withCheckedContinuation { continuation in
            blockedUpdateContinuation = continuation
        }
    }

    func end(
        activityID: String,
        content: ActivityContent<TimeTrackingActivityAttributes.ContentState>
    ) async {
        endCount += 1
        activities.removeAll { $0.id == activityID }
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
