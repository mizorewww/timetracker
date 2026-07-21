#if os(iOS) && canImport(ActivityKit)
import ActivityKit
import Foundation

nonisolated struct LiveActivityRegistration: Equatable, Sendable {
    let id: String
    let segmentID: String
}

@MainActor
protocol LiveActivitySystemClient: AnyObject {
    var areActivitiesEnabled: Bool { get }
    var activities: [LiveActivityRegistration] { get }

    func activityEnablementUpdates() -> AsyncStream<Bool>
    func request(
        attributes: TimeTrackingActivityAttributes,
        content: ActivityContent<TimeTrackingActivityAttributes.ContentState>
    ) throws -> LiveActivityRegistration
    func update(
        activityID: String,
        content: ActivityContent<TimeTrackingActivityAttributes.ContentState>
    ) async
    func end(
        activityID: String,
        content: ActivityContent<TimeTrackingActivityAttributes.ContentState>
    ) async
}

@MainActor
final class ActivityKitLiveActivitySystemClient: LiveActivitySystemClient {
    private let authorizationInfo = ActivityAuthorizationInfo()

    var areActivitiesEnabled: Bool {
        authorizationInfo.areActivitiesEnabled
    }

    var activities: [LiveActivityRegistration] {
        Activity<TimeTrackingActivityAttributes>.activities.map {
            LiveActivityRegistration(
                id: $0.id,
                segmentID: $0.attributes.segmentID
            )
        }
    }

    func activityEnablementUpdates() -> AsyncStream<Bool> {
        let source = authorizationInfo.activityEnablementUpdates
        return AsyncStream { continuation in
            let observationTask = Task { @MainActor in
                for await enabled in source {
                    guard Task.isCancelled == false else { break }
                    continuation.yield(enabled)
                }
                continuation.finish()
            }
            continuation.onTermination = { @Sendable _ in
                observationTask.cancel()
            }
        }
    }

    func request(
        attributes: TimeTrackingActivityAttributes,
        content: ActivityContent<TimeTrackingActivityAttributes.ContentState>
    ) throws -> LiveActivityRegistration {
        let activity = try Activity.request(
            attributes: attributes,
            content: content,
            pushType: nil
        )
        return LiveActivityRegistration(
            id: activity.id,
            segmentID: attributes.segmentID
        )
    }

    func update(
        activityID: String,
        content: ActivityContent<TimeTrackingActivityAttributes.ContentState>
    ) async {
        guard let activity = Activity<TimeTrackingActivityAttributes>.activities.first(where: {
            $0.id == activityID
        }) else { return }
        await activity.update(content)
    }

    func end(
        activityID: String,
        content: ActivityContent<TimeTrackingActivityAttributes.ContentState>
    ) async {
        guard let activity = Activity<TimeTrackingActivityAttributes>.activities.first(where: {
            $0.id == activityID
        }) else { return }
        await activity.end(content, dismissalPolicy: .immediate)
    }
}
#endif
