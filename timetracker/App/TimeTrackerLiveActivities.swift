#if os(iOS) && canImport(ActivityKit)
import ActivityKit
import Observation
import OSLog

nonisolated enum LiveActivityStatus: Equatable, Sendable {
    /// Allowed, no running timer.
    case ready
    case active
    /// Live Activities are off in iOS Settings.
    case denied
    /// The user swiped the running timer's activity away.
    case removed
    /// ActivityKit rejected the request; the next projection retries.
    case failed
}

/// Keeps at most one Live Activity, showing the primary running timer.
/// Projections are applied one at a time; only the newest pending one runs.
@MainActor
@Observable
final class LiveActivityCoordinator {
    static let shared = LiveActivityCoordinator()

    private static let logger = Logger(
        subsystem: AppIdentity.loggingSubsystem,
        category: "LiveActivity"
    )

    private(set) var status: LiveActivityStatus

    @ObservationIgnored private let authorizationInfo = ActivityAuthorizationInfo()
    @ObservationIgnored private var pendingProjection: CommittedMutationLiveActivityProjection?
    @ObservationIgnored private var lastProjection: CommittedMutationLiveActivityProjection?
    @ObservationIgnored private var applyTask: Task<Void, Never>?
    @ObservationIgnored private var authorizationTask: Task<Void, Never>?
    /// The segment whose activity this process requested. If the user removed
    /// it while the segment still runs, it is not re-requested until `retry()`
    /// or a different timer; an activity the system ended is re-requested.
    @ObservationIgnored private var requestedSegmentID: String?
    /// Set by `retry()` for the next reconcile only.
    @ObservationIgnored private var ignoresRemoval = false

    private init() {
        status = authorizationInfo.areActivitiesEnabled ? .ready : .denied
        let updates = authorizationInfo.activityEnablementUpdates
        authorizationTask = Task { @MainActor [weak self] in
            for await enabled in updates {
                guard let self else { return }
                if enabled {
                    if status == .denied {
                        retry()
                    }
                } else {
                    status = .denied
                }
            }
        }
    }

    /// Applies `projection` and waits until it and any newer pending one are
    /// applied. Throws when ActivityKit rejected the request so the caller can
    /// retry with its next projection.
    func apply(_ projection: CommittedMutationLiveActivityProjection) async throws {
        pendingProjection = projection
        if applyTask == nil {
            applyTask = Task { @MainActor [weak self] in
                await self?.drain()
            }
        }
        while let applyTask {
            await applyTask.value
        }
        if status == .failed {
            throw LiveActivityRequestError()
        }
    }

    func retry() {
        // Nothing projected yet: there is no activity to restore, but the
        // status must follow re-enabled Live Activities.
        guard let lastProjection else {
            status = authorizationInfo.areActivitiesEnabled ? .ready : .denied
            return
        }
        ignoresRemoval = true
        Task { @MainActor [weak self] in
            try? await self?.apply(lastProjection)
        }
    }

    private func drain() async {
        while let projection = pendingProjection {
            pendingProjection = nil
            lastProjection = projection
            await reconcile(projection)
        }
        applyTask = nil
    }

    private func reconcile(_ projection: CommittedMutationLiveActivityProjection) async {
        let ignoresRemoval = ignoresRemoval
        self.ignoresRemoval = false
        let activities = Activity<TimeTrackingActivityAttributes>.activities
        guard case let .active(timer) = projection else {
            for activity in activities {
                await activity.end(nil, dismissalPolicy: .immediate)
            }
            requestedSegmentID = nil
            status = authorizationInfo.areActivitiesEnabled ? .ready : .denied
            return
        }

        let content = ActivityContent(
            state: TimeTrackingActivityAttributes.ContentState(
                taskTitle: timer.taskTitle,
                taskPath: timer.taskPath,
                taskPathAbbreviated: timer.taskPathAbbreviated,
                iconName: timer.iconName,
                colorHex: timer.colorHex,
                startedAt: timer.startedAt
            ),
            staleDate: nil
        )
        let timerActivities = activities.filter {
            $0.attributes.segmentID == timer.segmentID
        }
        let current = timerActivities.first {
            [.pending, .active, .stale].contains($0.activityState)
        }
        for activity in activities where activity.id != current?.id {
            await activity.end(nil, dismissalPolicy: .immediate)
        }
        if let current {
            await current.update(content)
            requestedSegmentID = timer.segmentID
            status = .active
            return
        }
        let wasRemoved = timerActivities.contains { $0.activityState == .dismissed }
            || (requestedSegmentID == timer.segmentID && timerActivities.isEmpty)
        guard wasRemoved == false || ignoresRemoval else {
            requestedSegmentID = timer.segmentID
            status = .removed
            return
        }
        guard authorizationInfo.areActivitiesEnabled else {
            status = .denied
            return
        }
        do {
            _ = try Activity.request(
                attributes: TimeTrackingActivityAttributes(
                    segmentID: timer.segmentID,
                    taskID: timer.taskID
                ),
                content: content,
                pushType: nil
            )
            requestedSegmentID = timer.segmentID
            status = .active
        } catch {
            status = .failed
            Self.logger.error(
                "Failed to start Live Activity: \(String(describing: error), privacy: .public)"
            )
        }
    }
}

nonisolated struct LiveActivityRequestError: LocalizedError {
    var errorDescription: String? {
        "ActivityKit rejected the Live Activity request."
    }
}
#endif
