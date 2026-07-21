#if os(iOS) && canImport(ActivityKit)
import ActivityKit
import Foundation

nonisolated enum LiveActivityLifecycleState: Equatable, Sendable {
    case pending
    case active
    case stale
    case ended
    case dismissed

    var isTerminal: Bool {
        switch self {
        case .ended, .dismissed:
            true
        case .pending, .active, .stale:
            false
        }
    }

    init(_ state: ActivityState) {
        switch state {
        case .pending:
            self = .pending
        case .active:
            self = .active
        case .stale:
            self = .stale
        case .ended:
            self = .ended
        case .dismissed:
            self = .dismissed
        @unknown default:
            self = .ended
        }
    }
}

nonisolated struct LiveActivityRegistration: Equatable, Sendable {
    let id: String
    let segmentID: String
    let state: LiveActivityLifecycleState

    init(
        id: String,
        segmentID: String,
        state: LiveActivityLifecycleState = .active
    ) {
        self.id = id
        self.segmentID = segmentID
        self.state = state
    }
}

@MainActor
protocol LiveActivitySystemClient: AnyObject {
    var areActivitiesEnabled: Bool { get }
    var activities: [LiveActivityRegistration] { get }

    func activityEnablementUpdates() -> AsyncStream<Bool>
    func activityStateUpdates(
        for activityID: String
    ) -> AsyncStream<LiveActivityLifecycleState>
    func request(
        attributes: TimeTrackingActivityAttributes,
        content: ActivityContent<TimeTrackingActivityAttributes.ContentState>
    ) throws -> LiveActivityRegistration
    func update(
        activityID: String,
        content: ActivityContent<TimeTrackingActivityAttributes.ContentState>
    ) async -> LiveActivityRegistration?
    func end(
        activityID: String,
        content: ActivityContent<TimeTrackingActivityAttributes.ContentState>
    ) async
}

@MainActor
final class ActivityKitLiveActivitySystemClient: LiveActivitySystemClient {
    private let authorizationInfo = ActivityAuthorizationInfo()
    private var knownActivities: [
        String: Activity<TimeTrackingActivityAttributes>
    ] = [:]

    var areActivitiesEnabled: Bool {
        authorizationInfo.areActivitiesEnabled
    }

    var activities: [LiveActivityRegistration] {
        let activities = Activity<TimeTrackingActivityAttributes>.activities
        for activity in activities {
            knownActivities[activity.id] = activity
        }
        return activities.map {
            LiveActivityRegistration(
                id: $0.id,
                segmentID: $0.attributes.segmentID,
                state: LiveActivityLifecycleState($0.activityState)
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

    func activityStateUpdates(
        for activityID: String
    ) -> AsyncStream<LiveActivityLifecycleState> {
        guard let activity = activity(withID: activityID) else {
            return AsyncStream { continuation in
                continuation.yield(.ended)
                continuation.finish()
            }
        }
        let source = activity.activityStateUpdates
        let initial = LiveActivityLifecycleState(activity.activityState)
        return AsyncStream(bufferingPolicy: .bufferingNewest(1)) { continuation in
            continuation.yield(initial)
            let observationTask = Task { @MainActor [weak self] in
                var previous = initial
                for await state in source {
                    guard Task.isCancelled == false else { break }
                    let next = LiveActivityLifecycleState(state)
                    guard next != previous else { continue }
                    previous = next
                    continuation.yield(next)
                }
                continuation.finish()
                self?.knownActivities[activityID] = nil
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
        knownActivities[activity.id] = activity
        return LiveActivityRegistration(
            id: activity.id,
            segmentID: attributes.segmentID,
            state: LiveActivityLifecycleState(activity.activityState)
        )
    }

    func update(
        activityID: String,
        content: ActivityContent<TimeTrackingActivityAttributes.ContentState>
    ) async -> LiveActivityRegistration? {
        guard let activity = activity(withID: activityID) else { return nil }
        await activity.update(content)
        return LiveActivityRegistration(
            id: activity.id,
            segmentID: activity.attributes.segmentID,
            state: LiveActivityLifecycleState(activity.activityState)
        )
    }

    func end(
        activityID: String,
        content: ActivityContent<TimeTrackingActivityAttributes.ContentState>
    ) async {
        guard let activity = activity(withID: activityID) else { return }
        await activity.end(content, dismissalPolicy: .immediate)
        knownActivities[activityID] = nil
    }

    private func activity(
        withID activityID: String
    ) -> Activity<TimeTrackingActivityAttributes>? {
        if let knownActivity = knownActivities[activityID] {
            return knownActivity
        }
        guard let activity = Activity<TimeTrackingActivityAttributes>.activities.first(where: {
            $0.id == activityID
        }) else { return nil }
        knownActivities[activityID] = activity
        return activity
    }
}
#endif
