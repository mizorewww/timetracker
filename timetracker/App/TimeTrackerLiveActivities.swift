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
        guard reconciliationTask == nil else { return }
        reconciliationTask = Task { @MainActor [weak self] in
            guard let self else { return }
            await drain()
        }
    }

    func waitUntilIdle() async {
        while let reconciliationTask {
            await reconciliationTask.value
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

@MainActor
final class LiveActivityCoordinator {
    static let shared = LiveActivityCoordinator()

    private struct Request: Equatable {
        let segmentID: String
        let taskID: String
        let state: TimeTrackingActivityAttributes.ContentState
    }

    private enum DesiredState: Equatable {
        case inactive
        case active(Request)
    }

    private var lastRequest: Request?
    private let projectionService = LiveActivityProjectionService()
    private lazy var reconciler = LatestDesiredStateReconciler<DesiredState> { [weak self] state in
        guard let self else { return }
        await reconcile(state)
    }

    func sync(activeSegments: [TimeSegment], tasks: [TaskNode], now: Date) {
        guard let primary = projectionService.primarySegment(
            from: activeSegments,
            now: now
        ) else {
            let hasWork = lastRequest != nil
                || reconciler.isReconciling
                || !Activity<TimeTrackingActivityAttributes>.activities.isEmpty
            guard hasWork else { return }

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
        let hasMatchingActivity = Activity<TimeTrackingActivityAttributes>.activities.contains {
            $0.attributes.segmentID == request.segmentID
        }

        guard request != lastRequest || !hasMatchingActivity || reconciler.isReconciling else {
            return
        }
        reconciler.submit(.active(request))
    }

    private func reconcile(_ desiredState: DesiredState) async {
        switch desiredState {
        case .inactive:
            await endAllActivities()
            lastRequest = nil
        case .active(let request):
            if await updateOrStart(request) {
                lastRequest = request
            }
        }
    }

    private func updateOrStart(_ request: Request) async -> Bool {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else {
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
        let activities = Activity<TimeTrackingActivityAttributes>.activities

        if let existing = activities.first(where: {
            $0.attributes.segmentID == request.segmentID
        }) {
            await existing.update(content)

            for stale in activities where stale.id != existing.id {
                await stale.end(content, dismissalPolicy: .immediate)
            }
            return true
        } else {
            for stale in activities {
                await stale.end(content, dismissalPolicy: .immediate)
            }

            do {
                _ = try Activity.request(attributes: attributes, content: content, pushType: nil)
                return true
            } catch {
                return false
            }
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
        for activity in Activity<TimeTrackingActivityAttributes>.activities {
            await activity.end(content, dismissalPolicy: .immediate)
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
}
#else
extension TimeTrackerStore {
    func syncLiveActivitiesIfAvailable() {}
}
#endif
