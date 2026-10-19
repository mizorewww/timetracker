import Foundation

/// Delivers an in-process acceleration signal after a durable store mutation.
/// Persistent history and CloudKit remain the cross-process convergence path.
@MainActor
enum StoreMutationBroadcaster {
    static let notification = Notification.Name(
        "\(AppIdentity.bundleIdentifier).storeMutationCommitted"
    )
    private static let eventsUserInfoKey = "events"
    private static var pendingEvents: Set<StoreDomainEvent> = []
    private weak static var pendingSource: TimeTrackerStore?
    private static var hasPendingPost = false

    /// Coalesces every mutation of the current main-actor turn into one post.
    /// The mutating scene completes its own refresh and returns before sibling
    /// scenes perform their read-only catch-up. When several sources mutate in
    /// the same turn, the post names no source and every scene catches up.
    static func publish(events: Set<StoreDomainEvent>, source: TimeTrackerStore? = nil) {
        guard events.isEmpty == false else { return }
        if hasPendingPost {
            if pendingSource !== source {
                pendingSource = nil
            }
        } else {
            pendingSource = source
            hasPendingPost = true
            // Runs after the current main-actor job, so the mutating scene
            // finishes its own refresh before siblings catch up.
            Task { @MainActor in
                post()
            }
        }
        pendingEvents.formUnion(events)
    }

    private static func post() {
        let events = pendingEvents
        let source = pendingSource
        pendingEvents = []
        pendingSource = nil
        hasPendingPost = false
        NotificationCenter.default.post(
            name: notification,
            object: source,
            userInfo: [eventsUserInfoKey: events]
        )
    }

    static func events(from notification: Notification) -> Set<StoreDomainEvent>? {
        notification.userInfo?[eventsUserInfoKey] as? Set<StoreDomainEvent>
    }
}
