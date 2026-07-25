import Foundation

/// Delivers an in-process acceleration signal after a durable store mutation.
/// Persistent history and CloudKit remain the cross-process convergence path.
@MainActor
enum StoreMutationBroadcaster {
    private static let notificationName = Notification.Name(
        "me.mezorewww.timetracker.storeMutationCommitted"
    )
    private static let eventsUserInfoKey = "events"

    static func publish(events: Set<StoreDomainEvent>, source: TimeTrackerStore? = nil) {
        guard events.isEmpty == false else { return }
        NotificationCenter.default.post(
            name: notificationName,
            object: source,
            userInfo: [eventsUserInfoKey: events]
        )
    }

    static func events(from notification: Notification) -> Set<StoreDomainEvent>? {
        notification.userInfo?[eventsUserInfoKey] as? Set<StoreDomainEvent>
    }

    static var notification: Notification.Name {
        notificationName
    }
}
