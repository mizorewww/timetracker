import Foundation

/// Delivers an in-process acceleration signal after a durable store mutation.
/// Persistent history and CloudKit remain the cross-process convergence path.
@MainActor
enum StoreMutationBroadcaster {
    private struct PendingBroadcast {
        let events: Set<StoreDomainEvent>
        weak var source: TimeTrackerStore?
    }

    private static let notificationName = Notification.Name(
        "me.mezorewww.timetracker.storeMutationCommitted"
    )
    private static let eventsUserInfoKey = "events"
    private static var pendingBroadcasts: [PendingBroadcast] = []
    private static var drainTask: Task<Void, Never>?

    static func publish(events: Set<StoreDomainEvent>, source: TimeTrackerStore? = nil) {
        guard events.isEmpty == false else { return }
        pendingBroadcasts.append(
            PendingBroadcast(events: events, source: source)
        )
        guard drainTask == nil else { return }
        drainTask = Task { @MainActor in
            // The mutating scene completes its own visible projection and
            // returns before sibling scenes perform their read-only catch-up.
            await Task.yield()
            drainPendingBroadcasts()
        }
    }

    static func waitUntilIdle() async {
        while let task = drainTask {
            await task.value
        }
    }

    private static func drainPendingBroadcasts() {
        while pendingBroadcasts.isEmpty == false {
            let broadcast = pendingBroadcasts.removeFirst()
            NotificationCenter.default.post(
                name: notificationName,
                object: broadcast.source,
                userInfo: [eventsUserInfoKey: broadcast.events]
            )
        }
        drainTask = nil
    }

    static func events(from notification: Notification) -> Set<StoreDomainEvent>? {
        notification.userInfo?[eventsUserInfoKey] as? Set<StoreDomainEvent>
    }

    static var notification: Notification.Name {
        notificationName
    }
}
