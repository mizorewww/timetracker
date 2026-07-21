import Foundation

/// Serializes destructive asynchronous system-surface updates while retaining
/// only the newest desired state. An operation that has already crossed an
/// `await` cannot be undone, so newer work runs after it and restores the final
/// state instead of racing it.
@MainActor
final class LatestDesiredStateReconciler<State: Equatable> {
    typealias Operation = @MainActor (State) async -> Void

    private let operation: Operation
    private(set) var desiredState: State?
    private var desiredRevision: UInt = 0
    private var reconciliationTask: Task<Void, Never>?

    init(operation: @escaping Operation) {
        self.operation = operation
    }

    var isReconciling: Bool {
        reconciliationTask != nil
    }

    func submit(_ state: State) {
        if desiredState == state, reconciliationTask != nil {
            return
        }
        desiredState = state
        desiredRevision &+= 1
        startReconciliationIfNeeded()
    }

    func waitUntilIdle() async {
        while let reconciliationTask {
            await reconciliationTask.value
        }
    }

    /// Replays the retained desired state after a recoverable system-surface
    /// failure without requiring the timer mutation to happen again.
    func retryDesiredState() {
        guard desiredState != nil else { return }
        desiredRevision &+= 1
        startReconciliationIfNeeded()
    }

    private func startReconciliationIfNeeded() {
        guard reconciliationTask == nil else { return }
        reconciliationTask = Task { @MainActor [weak self] in
            guard let self else { return }
            await drain()
        }
    }

    private func drain() async {
        defer { reconciliationTask = nil }
        while Task.isCancelled == false, let desiredState {
            let revision = desiredRevision
            await operation(desiredState)
            guard desiredRevision != revision else { return }
        }
    }
}

#if os(iOS) && canImport(ActivityKit)
import ActivityKit
import Observation
import OSLog

@MainActor
@Observable
final class LiveActivityCoordinator {
    static let shared = LiveActivityCoordinator(
        client: ActivityKitLiveActivitySystemClient()
    )

    private static let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "me.mezorewww.timetracker",
        category: "LiveActivity"
    )

    private struct Request: Equatable {
        let segmentID: String
        let taskID: String
        let state: TimeTrackingActivityAttributes.ContentState
    }

    private enum DesiredState: Equatable {
        case inactive
        case active(Request)
    }

    private(set) var status: LiveActivityStatus

    @ObservationIgnored private var lastRequest: Request?
    @ObservationIgnored private let projectionService = LiveActivityProjectionService()
    @ObservationIgnored private let client: any LiveActivitySystemClient
    @ObservationIgnored private var authorizationObservationTask: Task<Void, Never>?
    @ObservationIgnored private lazy var reconciler = LatestDesiredStateReconciler<DesiredState> { [weak self] state in
        guard let self else { return }
        await reconcile(state)
    }

    init(client: any LiveActivitySystemClient) {
        self.client = client
        status = client.areActivitiesEnabled
            ? .ready
            : .unavailable(.denied)
        observeAuthorizationChanges()
    }

    deinit {
        authorizationObservationTask?.cancel()
    }

    func sync(activeSegments: [TimeSegment], tasks: [TaskNode], now: Date) {
        guard let primary = projectionService.primarySegment(
            from: activeSegments,
            now: now
        ) else {
            let hasRetainedActiveState: Bool
            if case .active? = reconciler.desiredState {
                hasRetainedActiveState = true
            } else {
                hasRetainedActiveState = false
            }
            let hasWork = lastRequest != nil
                || reconciler.isReconciling
                || hasRetainedActiveState
                || !client.activities.isEmpty
            guard hasWork else {
                status = client.areActivitiesEnabled
                    ? .ready
                    : .unavailable(.denied)
                return
            }

            lastRequest = nil
            reconciler.submit(.inactive)
            return
        }

        let projection = projectionService.taskProjection(
            taskID: primary.taskID,
            tasks: tasks,
            fallbackTitle: primary.titleSnapshotFallback
        )
        let state = TimeTrackingActivityAttributes.ContentState(
            taskTitle: projection.title,
            taskPath: projection.path,
            taskPathAbbreviated: projection.abbreviatedPath,
            iconName: projection.iconName,
            colorHex: projection.colorHex,
            startedAt: primary.startedAt,
            additionalTimerCount: 0
        )
        let request = Request(
            segmentID: primary.id.uuidString,
            taskID: primary.taskID.uuidString,
            state: state
        )
        let hasMatchingActivity = client.activities.contains {
            $0.segmentID == request.segmentID
        }

        guard request != lastRequest || !hasMatchingActivity || reconciler.isReconciling else {
            status = client.areActivitiesEnabled
                ? .active
                : .unavailable(.denied)
            return
        }
        reconciler.submit(.active(request))
    }

    func waitUntilIdle() async {
        await reconciler.waitUntilIdle()
    }

    func retryLatestDesiredState() {
        guard reconciler.desiredState != nil else {
            status = client.areActivitiesEnabled
                ? .ready
                : .unavailable(.denied)
            return
        }
        status = .synchronizing
        reconciler.retryDesiredState()
    }

    private func reconcile(_ desiredState: DesiredState) async {
        status = .synchronizing
        switch desiredState {
        case .inactive:
            await endAllActivities()
            lastRequest = nil
            status = client.areActivitiesEnabled
                ? .ready
                : .unavailable(.denied)
        case .active(let request):
            if await updateOrStart(request) {
                lastRequest = request
                status = client.areActivitiesEnabled
                    ? .active
                    : .unavailable(.denied)
            }
        }
    }

    private func updateOrStart(_ request: Request) async -> Bool {
        guard client.areActivitiesEnabled else {
            status = .unavailable(.denied)
            Self.logger.notice(
                "Skipped Live Activity synchronization because Live Activities are disabled in system settings"
            )
            return false
        }

        let attributes = TimeTrackingActivityAttributes(
            segmentID: request.segmentID,
            taskID: request.taskID
        )
        let content = ActivityContent(
            state: request.state,
            staleDate: LiveActivityTimingPolicy.staleDate(for: request.state.startedAt)
        )
        let activities = client.activities

        if let existing = activities.first(where: {
            $0.segmentID == request.segmentID
        }) {
            await client.update(activityID: existing.id, content: content)

            for stale in activities where stale.id != existing.id {
                await client.end(activityID: stale.id, content: content)
            }
            return true
        } else {
            for stale in activities {
                await client.end(activityID: stale.id, content: content)
            }

            do {
                _ = try client.request(attributes: attributes, content: content)
                return true
            } catch {
                status = .unavailable(LiveActivityFailure(error))
                Self.logger.error(
                    "Failed to start Live Activity: \(String(describing: error), privacy: .public)"
                )
                return false
            }
        }
    }

    private func observeAuthorizationChanges() {
        let updates = client.activityEnablementUpdates()
        authorizationObservationTask = Task { @MainActor [weak self] in
            for await areActivitiesEnabled in updates {
                guard let self else { return }
                handleAuthorizationChange(areActivitiesEnabled)
            }
        }
    }

    private func handleAuthorizationChange(_ areActivitiesEnabled: Bool) {
        guard areActivitiesEnabled else {
            status = .unavailable(.denied)
            return
        }
        guard status == .unavailable(.denied) else { return }

        status = .ready
        if case .active? = reconciler.desiredState {
            retryLatestDesiredState()
        }
    }

    private func endAllActivities() async {
        let content = ActivityContent(
            state: TimeTrackingActivityAttributes.ContentState(
                taskTitle: AppStrings.localized("live.timer.endedTitle"),
                taskPath: "",
                taskPathAbbreviated: nil,
                iconName: "checkmark",
                colorHex: "34C759",
                startedAt: Date(),
                additionalTimerCount: 0
            ),
            staleDate: nil
        )
        for activity in client.activities {
            await client.end(activityID: activity.id, content: content)
        }
    }
}

extension LiveActivityFailure {
    init(_ error: Error) {
        guard let authorizationError = error as? ActivityAuthorizationError else {
            self = .system
            return
        }

        switch authorizationError {
        case .attributesTooLarge:
            self = .payloadTooLarge
        case .unsupported:
            self = .unsupported
        case .denied:
            self = .denied
        case .globalMaximumExceeded, .targetMaximumExceeded:
            self = .capacity
        case .visibility:
            self = .backgroundStart
        case .unsupportedTarget,
             .missingProcessIdentifier,
             .unentitled,
             .malformedActivityIdentifier:
            self = .configuration
        case .persistenceFailure:
            self = .system
        case .reconnectNotPermitted:
            self = .configuration
        @unknown default:
            self = .system
        }
    }
}

private extension TimeSegment {
    var titleSnapshotFallback: String {
        AppStrings.activeTimers
    }
}

extension TimeTrackerStore {
    func syncLiveActivitiesIfAvailable() {
        LiveActivityCoordinator.shared.sync(activeSegments: activeSegments, tasks: tasks, now: Date())
    }

    func waitForLiveActivityReconciliationIfAvailable() async {
        await LiveActivityCoordinator.shared.waitUntilIdle()
    }
}
#else
extension TimeTrackerStore {
    func syncLiveActivitiesIfAvailable() {}
    func waitForLiveActivityReconciliationIfAvailable() async {}
}
#endif
