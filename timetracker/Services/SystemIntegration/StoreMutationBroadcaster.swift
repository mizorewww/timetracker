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
    private static let syncConflictPromptNotificationName = Notification.Name(
        "TimeTrackerSyncConflictPromptChanged"
    )
    private static let eventsUserInfoKey = "events"
    private static let pendingBroadcastRetentionLimit = 64
    private static var pendingBroadcasts: [PendingBroadcast] = []
    private static var drainTask: Task<Void, Never>?

    static func publish(events: Set<StoreDomainEvent>, source: TimeTrackerStore? = nil) {
        guard events.isEmpty == false else { return }
        let boundedEvents = StoreDomainEventBatchLimiter.bounded(events)
        let alreadyCollapsed = pendingBroadcasts.count == 1
            && pendingBroadcasts[0].events == [.fullSync]
            && pendingBroadcasts[0].source == nil
        if alreadyCollapsed {
            return
        }
        if boundedEvents == [.fullSync], source == nil {
            pendingBroadcasts = [
                PendingBroadcast(events: [.fullSync], source: nil),
            ]
        } else if pendingBroadcasts.count >= pendingBroadcastRetentionLimit {
            // Every observer reads the latest committed facts. Under an
            // unusual burst, one source-neutral full refresh subsumes every
            // queued source-specific catch-up without retaining their IDs.
            pendingBroadcasts = [
                PendingBroadcast(events: [.fullSync], source: nil),
            ]
        } else {
            pendingBroadcasts.append(
                PendingBroadcast(events: boundedEvents, source: source)
            )
        }
        guard drainTask == nil else { return }
        drainTask = Task { @MainActor in
            // The mutating scene completes its own visible projection and
            // returns before sibling scenes perform their read-only catch-up.
            await Task.yield()
            drainPendingBroadcasts()
        }
    }

    private static func drainPendingBroadcasts() {
        while pendingBroadcasts.isEmpty == false {
            let batch = pendingBroadcasts
            pendingBroadcasts.removeAll(keepingCapacity: true)
            for broadcast in batch {
                NotificationCenter.default.post(
                    name: notificationName,
                    object: broadcast.source,
                    userInfo: [eventsUserInfoKey: broadcast.events]
                )
            }
        }
        drainTask = nil
    }

    static func events(from notification: Notification) -> Set<StoreDomainEvent>? {
        notification.userInfo?[eventsUserInfoKey] as? Set<StoreDomainEvent>
    }

    static var notification: Notification.Name {
        notificationName
    }

    static func publishSyncConflictPromptChange() {
        NotificationCenter.default.post(
            name: syncConflictPromptNotificationName,
            object: nil
        )
    }

    static var syncConflictPromptNotification: Notification.Name {
        syncConflictPromptNotificationName
    }
}
