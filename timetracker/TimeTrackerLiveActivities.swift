import Foundation

#if os(iOS) && canImport(ActivityKit)
import ActivityKit

struct TimeTrackingActivityAttributes: ActivityAttributes {
    public struct ContentState: Codable, Hashable {
        var taskTitle: String
        var taskPath: String
        var iconName: String
        var colorHex: String
        var startedAt: Date
        var additionalTimerCount: Int
    }

    var taskID: String
}

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
            taskPath: task?.path.replacingOccurrences(of: "/", with: " / ") ?? "时间记录",
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
                taskTitle: "计时已结束",
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
}

private extension TimeSegment {
    var titleSnapshotFallback: String {
        "正在计时"
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
