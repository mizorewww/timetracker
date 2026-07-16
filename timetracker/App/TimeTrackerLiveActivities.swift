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
        let taskID: String
        let state: TimeTrackingActivityAttributes.ContentState
    }

    private enum DesiredState: Equatable {
        case inactive
        case active(Request)
    }

    private var lastRequest: Request?
    private lazy var reconciler = LatestDesiredStateReconciler<DesiredState> { [weak self] state in
        guard let self else { return }
        await reconcile(state)
    }

    func sync(activeSegments: [TimeSegment], tasks: [TaskNode], now: Date) {
        let usableSegments = activeSegments
            .filter { $0.deletedAt == nil && $0.startedAt <= now }
            .sorted { $0.startedAt < $1.startedAt }

        guard let primary = usableSegments.first else {
            let hasWork = lastRequest != nil
                || reconciler.isReconciling
                || !Activity<TimeTrackingActivityAttributes>.activities.isEmpty
            guard hasWork else { return }

            lastRequest = nil
            reconciler.submit(.inactive)
            return
        }

        let task = tasks.first { $0.id == primary.taskID }
        let state = TimeTrackingActivityAttributes.ContentState(
            taskTitle: task?.title ?? primary.titleSnapshotFallback,
            taskPath: task.map { displayPath(for: $0, tasks: tasks) } ?? AppStrings.localized("live.timer.defaultPath"),
            iconName: task?.iconName ?? "timer",
            colorHex: task?.colorHex ?? "0A84FF",
            startedAt: primary.startedAt,
            additionalTimerCount: max(0, usableSegments.count - 1)
        )
        let request = Request(taskID: primary.taskID.uuidString, state: state)
        let hasMatchingActivity = Activity<TimeTrackingActivityAttributes>.activities.contains {
            $0.attributes.taskID == request.taskID
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

        let attributes = TimeTrackingActivityAttributes(taskID: request.taskID)
        let content = ActivityContent(
            state: request.state,
            staleDate: LiveActivityTimingPolicy.staleDate(for: request.state.startedAt)
        )
        let activities = Activity<TimeTrackingActivityAttributes>.activities

        if let existing = activities.first(where: { $0.attributes.taskID == request.taskID }) {
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

    private func displayPath(for task: TaskNode, tasks: [TaskNode]) -> String {
        var parentNames: [String] = []
        var cursor = task.parentID
        var visited: Set<UUID> = [task.id]
        while let parentID = cursor,
              visited.insert(parentID).inserted,
              let parent = tasks.first(where: { $0.id == parentID }) {
            parentNames.insert(parent.title, at: 0)
            cursor = parent.parentID
        }
        return parentNames.isEmpty ? AppStrings.rootTask : parentNames.joined(separator: " / ")
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
