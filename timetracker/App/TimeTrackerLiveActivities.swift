import Foundation

#if os(iOS) && canImport(ActivityKit)
import ActivityKit

@MainActor
final class LiveActivityCoordinator {
    static let shared = LiveActivityCoordinator()

    private struct Request: Equatable {
        let taskID: String
        let state: TimeTrackingActivityAttributes.ContentState
    }

    private var lastRequest: Request?
    private var pendingRequest: Request?
    private var generation = 0

    func sync(activeSegments: [TimeSegment], tasks: [TaskNode], now: Date) {
        let usableSegments = activeSegments
            .filter { $0.deletedAt == nil && $0.startedAt <= now }
            .sorted { $0.startedAt < $1.startedAt }

        guard let primary = usableSegments.first else {
            let hasWork = lastRequest != nil
                || pendingRequest != nil
                || !Activity<TimeTrackingActivityAttributes>.activities.isEmpty
            guard hasWork else { return }

            generation &+= 1
            let expectedGeneration = generation
            lastRequest = nil
            pendingRequest = nil
            Task { [weak self] in
                await self?.endAllActivities(expectedGeneration: expectedGeneration)
            }
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

        guard request != pendingRequest else { return }
        guard request != lastRequest || !hasMatchingActivity else { return }

        generation &+= 1
        let expectedGeneration = generation
        pendingRequest = request
        Task { [weak self] in
            await self?.updateOrStart(request, expectedGeneration: expectedGeneration)
        }
    }

    private func updateOrStart(
        _ request: Request,
        expectedGeneration: Int
    ) async {
        guard expectedGeneration == generation else { return }
        guard ActivityAuthorizationInfo().areActivitiesEnabled else {
            finish(request, expectedGeneration: expectedGeneration, succeeded: false)
            return
        }

        let attributes = TimeTrackingActivityAttributes(taskID: request.taskID)
        let content = ActivityContent(
            state: request.state,
            staleDate: request.state.startedAt.addingTimeInterval(8 * 60 * 60)
        )
        let activities = Activity<TimeTrackingActivityAttributes>.activities

        if let existing = activities.first(where: { $0.attributes.taskID == request.taskID }) {
            await existing.update(content)
            guard expectedGeneration == generation else { return }

            for stale in activities where stale.id != existing.id {
                await stale.end(content, dismissalPolicy: .immediate)
                guard expectedGeneration == generation else { return }
            }
            finish(request, expectedGeneration: expectedGeneration, succeeded: true)
        } else {
            for stale in activities {
                await stale.end(content, dismissalPolicy: .immediate)
                guard expectedGeneration == generation else { return }
            }

            do {
                _ = try Activity.request(attributes: attributes, content: content, pushType: nil)
                finish(request, expectedGeneration: expectedGeneration, succeeded: true)
            } catch {
                finish(request, expectedGeneration: expectedGeneration, succeeded: false)
            }
        }
    }

    private func finish(_ request: Request, expectedGeneration: Int, succeeded: Bool) {
        guard expectedGeneration == generation else { return }
        if succeeded {
            lastRequest = request
        }
        if pendingRequest == request {
            pendingRequest = nil
        }
    }

    private func endAllActivities(expectedGeneration: Int) async {
        guard expectedGeneration == generation else { return }
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
            guard expectedGeneration == generation else { return }
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
