import Foundation

#if os(iOS) && canImport(ActivityKit)
import ActivityKit

@MainActor
final class LiveActivityCoordinator {
    static let shared = LiveActivityCoordinator()

    private var lastSignature: String?

    func sync(activeSegments: [TimeSegment], tasks: [TaskNode], now: Date) {
        let usableSegments = activeSegments
            .filter { $0.deletedAt == nil && $0.startedAt <= now }
            .sorted { $0.startedAt < $1.startedAt }

        guard let primary = usableSegments.first else {
            lastSignature = nil
            Task {
                await endAllActivities()
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
        let attributes = TimeTrackingActivityAttributes(taskID: primary.taskID.uuidString)
        let signature = "\(attributes.taskID)|\(state.taskTitle)|\(state.taskPath)|\(state.iconName)|\(state.colorHex)|\(state.startedAt.timeIntervalSince1970)|\(state.additionalTimerCount)"

        guard signature != lastSignature else { return }
        lastSignature = signature

        Task {
            await updateOrStart(attributes: attributes, state: state)
        }
    }

    private func updateOrStart(
        attributes: TimeTrackingActivityAttributes,
        state: TimeTrackingActivityAttributes.ContentState
    ) async {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }
        let content = ActivityContent(state: state, staleDate: nil)
        let activities = Activity<TimeTrackingActivityAttributes>.activities

        if let existing = activities.first {
            await existing.update(content)
            for stale in activities.dropFirst() {
                await stale.end(content, dismissalPolicy: .immediate)
            }
        } else {
            do {
                _ = try Activity.request(attributes: attributes, content: content, pushType: nil)
            } catch {
                lastSignature = nil
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
        while let parentID = cursor, let parent = tasks.first(where: { $0.id == parentID }) {
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
