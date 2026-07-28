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

    private struct SynchronizationResult {
        let registration: LiveActivityRegistration
        let didApplyRequest: Bool
    }

    private enum DesiredState: Equatable {
        case inactive
        case active(Request)
    }

    private(set) var status: LiveActivityStatus

    @ObservationIgnored private var lastRequest: Request?
    @ObservationIgnored private let client: any LiveActivitySystemClient
    @ObservationIgnored private var authorizationObservationTask: Task<Void, Never>?
    @ObservationIgnored private var activityStateObservationTask: Task<Void, Never>?
    @ObservationIgnored private var observedActivityID: String?
    @ObservationIgnored private var observedSegmentID: String?
    @ObservationIgnored private var dismissedSegmentID: String?
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
        activityStateObservationTask?.cancel()
    }

    func sync(activeSegments: [TimeSegment], tasks: [TaskNode], now: Date) {
        sync(projection: CommittedMutationLiveActivityProjection.materialize(
            activeSegments: activeSegments,
            tasks: tasks,
            now: now
        ))
    }

    func sync(projection: CommittedMutationLiveActivityProjection) {
        guard case let .active(projection) = projection else {
            dismissedSegmentID = nil
            let hasRetainedActiveState = if case .active? = reconciler.desiredState {
                true
            } else {
                false
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
            cancelActivityStateObservation()
            return
        }

        let state = TimeTrackingActivityAttributes.ContentState(
            taskTitle: projection.taskTitle,
            taskPath: projection.taskPath,
            taskPathAbbreviated: projection.taskPathAbbreviated,
            iconName: projection.iconName,
            colorHex: projection.colorHex,
            startedAt: projection.startedAt,
            additionalTimerCount: 0
        )
        let request = Request(
            segmentID: projection.segmentID,
            taskID: projection.taskID,
            state: state
        )
        if dismissedSegmentID != nil,
           dismissedSegmentID != request.segmentID
        {
            dismissedSegmentID = nil
        }
        if dismissedSegmentID == request.segmentID {
            lastRequest = request
            status = .unavailable(.removed)
            return
        }
        let matchingActivities = client.activities.filter {
            $0.segmentID == request.segmentID
        }
        let matchingActivity = matchingActivities.first {
            !$0.state.isTerminal
        } ?? matchingActivities.first
        if matchingActivity?.state == .dismissed {
            dismissedSegmentID = request.segmentID
            lastRequest = request
            cancelActivityStateObservation()
            status = .unavailable(.removed)
            reconciler.submit(.active(request))
            return
        }

        guard request != lastRequest
            || matchingActivity?.state == .stale
            || matchingActivity?.state.isTerminal == true
            || matchingActivity == nil
            || reconciler.isReconciling
        else {
            if let matchingActivity {
                observeActivityState(of: matchingActivity)
                publishStatus(for: matchingActivity.state)
            }
            return
        }
        reconciler.submit(.active(request))
    }

    func waitUntilIdle() async {
        await reconciler.waitUntilIdle()
    }

    func retryLatestDesiredState() {
        retryRetainedDesiredState(clearingRemovalSuppression: true)
    }

    private func retryRetainedDesiredState(
        clearingRemovalSuppression: Bool
    ) {
        guard reconciler.desiredState != nil else {
            status = client.areActivitiesEnabled
                ? .ready
                : .unavailable(.denied)
            return
        }
        if clearingRemovalSuppression,
           case let .active(request)? = reconciler.desiredState,
           dismissedSegmentID == request.segmentID
        {
            dismissedSegmentID = nil
        }
        status = .synchronizing
        reconciler.retryDesiredState()
    }

    private func reconcile(_ desiredState: DesiredState) async {
        status = .synchronizing
        switch desiredState {
        case .inactive:
            await endAllActivities()
            guard reconciler.desiredState == desiredState else { return }
            lastRequest = nil
            status = client.areActivitiesEnabled
                ? .ready
                : .unavailable(.denied)
        case let .active(request):
            if let result = await updateOrStart(request) {
                guard reconciler.desiredState == desiredState else { return }
                if result.didApplyRequest {
                    lastRequest = request
                }
                observeActivityState(of: result.registration)
                publishStatus(for: result.registration.state)
            }
        }
    }

    private func updateOrStart(
        _ request: Request
    ) async -> SynchronizationResult? {
        guard dismissedSegmentID != request.segmentID else {
            status = .unavailable(.removed)
            return nil
        }
        guard client.areActivitiesEnabled else {
            status = .unavailable(.denied)
            Self.logger.notice(
                "Skipped Live Activity synchronization because Live Activities are disabled in system settings"
            )
            return nil
        }

        let attributes = TimeTrackingActivityAttributes(
            segmentID: request.segmentID,
            taskID: request.taskID
        )
        let content = ActivityContent(
            state: request.state,
            staleDate: nil
        )
        let activities = client.activities

        if let existing = activities.first(where: {
            $0.segmentID == request.segmentID && !$0.state.isTerminal
        }) {
            let current: LiveActivityRegistration?
            let didApplyRequest: Bool
            switch existing.state {
            case .pending:
                current = existing
                didApplyRequest = request == lastRequest
            case .active, .stale:
                current = await client.update(
                    activityID: existing.id,
                    content: content
                )
                didApplyRequest = true
                guard dismissedSegmentID != request.segmentID else {
                    status = .unavailable(.removed)
                    return nil
                }
            case .ended, .dismissed:
                current = nil
                didApplyRequest = false
            }

            if current?.state == .dismissed {
                dismissedSegmentID = request.segmentID
                status = .unavailable(.removed)
                return nil
            }
            if let current, current.state.isTerminal == false,
               current.state != .stale
            {
                for stale in activities where stale.id != current.id {
                    await client.end(activityID: stale.id, content: content)
                    guard dismissedSegmentID != request.segmentID else {
                        status = .unavailable(.removed)
                        return nil
                    }
                }
                return SynchronizationResult(
                    registration: current,
                    didApplyRequest: didApplyRequest
                )
            }
        }

        for stale in activities {
            await client.end(activityID: stale.id, content: content)
            guard dismissedSegmentID != request.segmentID else {
                status = .unavailable(.removed)
                return nil
            }
        }

        guard dismissedSegmentID != request.segmentID else {
            status = .unavailable(.removed)
            return nil
        }
        do {
            let registration = try client.request(
                attributes: attributes,
                content: content
            )
            if registration.state == .dismissed {
                dismissedSegmentID = request.segmentID
                status = .unavailable(.removed)
                return nil
            }
            guard registration.state.isTerminal == false else {
                status = .unavailable(.system)
                return nil
            }
            return SynchronizationResult(
                registration: registration,
                didApplyRequest: true
            )
        } catch {
            status = .unavailable(LiveActivityFailure(error))
            Self.logger.error(
                "Failed to start Live Activity: \(String(describing: error), privacy: .public)"
            )
            return nil
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
            retryRetainedDesiredState(clearingRemovalSuppression: false)
        }
    }

    private func observeActivityState(
        of registration: LiveActivityRegistration
    ) {
        guard observedActivityID != registration.id else { return }
        activityStateObservationTask?.cancel()
        observedActivityID = registration.id
        observedSegmentID = registration.segmentID
        let updates = client.activityStateUpdates(for: registration.id)
        activityStateObservationTask = Task { @MainActor [weak self] in
            for await state in updates {
                guard let self else { return }
                handleActivityStateChange(
                    state,
                    activityID: registration.id,
                    segmentID: registration.segmentID
                )
            }
        }
    }

    private func cancelActivityStateObservation() {
        activityStateObservationTask?.cancel()
        activityStateObservationTask = nil
        observedActivityID = nil
        observedSegmentID = nil
    }

    private func handleActivityStateChange(
        _ state: LiveActivityLifecycleState,
        activityID: String,
        segmentID: String
    ) {
        guard observedActivityID == activityID,
              observedSegmentID == segmentID,
              case let .active(request)? = reconciler.desiredState,
              request.segmentID == segmentID
        else {
            return
        }

        switch state {
        case .active:
            if request != lastRequest {
                status = .synchronizing
                reconciler.retryDesiredState()
            } else {
                publishStatus(for: state)
            }
        case .pending:
            status = .synchronizing
        case .stale:
            status = .synchronizing
            reconciler.retryDesiredState()
        case .ended:
            cancelActivityStateObservation()
            status = .synchronizing
            reconciler.retryDesiredState()
        case .dismissed:
            cancelActivityStateObservation()
            dismissedSegmentID = segmentID
            status = .unavailable(.removed)
        }
    }

    private func publishStatus(for state: LiveActivityLifecycleState) {
        guard client.areActivitiesEnabled else {
            status = .unavailable(.denied)
            return
        }
        switch state {
        case .active:
            status = .active
        case .pending, .stale:
            status = .synchronizing
        case .ended, .dismissed:
            status = .unavailable(.system)
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
