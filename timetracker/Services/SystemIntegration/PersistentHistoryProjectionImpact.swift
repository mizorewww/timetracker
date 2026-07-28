import Foundation

/// Converts type-erased SwiftData history changes into conservative domain
/// invalidations. Persistent history exposes entity names but not the
/// command-level receipt, so IDs and ranges intentionally remain unspecified.
///
/// Unknown future entities fall back to `.fullSync`: acknowledging an opaque
/// history frontier after doing extra work is safe, while skipping a new
/// synced model could permanently hide that change from a projection lane.
nonisolated enum PersistentHistoryProjectionImpact {
    static func events(
        forEntityNames entityNames: Set<String>
    ) -> Set<StoreDomainEvent> {
        var events: Set<StoreDomainEvent> = []
        for entityName in entityNames {
            switch entityName {
            case "TaskNode",
                 "TaskCategory",
                 "TaskCategoryAssignment",
                 "TaskRecurrenceRule",
                 "TaskRecurrenceOccurrence",
                 "TaskQuantityGoal",
                 "TaskQuantityEntry":
                events.insert(.taskChanged(
                    taskID: nil,
                    affectedAncestorIDs: []
                ))
            case "TimeSession", "TimeSegment":
                events.insert(.ledgerChanged(
                    taskID: nil,
                    dateInterval: nil,
                    isVisible: true
                ))
            case "PomodoroRun":
                events.insert(.pomodoroChanged(
                    runID: nil,
                    sessionID: nil,
                    taskID: nil
                ))
            case "CountdownEvent":
                events.insert(.countdownChanged)
            case "SyncedPreference":
                events.insert(.preferenceChanged(key: nil))
            case "ChecklistItem", "ChecklistItemVisual":
                events.insert(.checklistChanged(
                    taskID: nil,
                    affectedAncestorIDs: []
                ))
            case "InboxItem",
                 "InboxSuggestion",
                 "InboxCaptureReceipt":
                events.insert(.inboxChanged(itemIDs: []))
            default:
                return [.fullSync]
            }
        }
        return StoreDomainEventBatchLimiter.bounded(events)
    }

    static func affects(
        lane: PersistentHistoryProjectionLane,
        events: Set<StoreDomainEvent>
    ) -> Bool {
        events.contains { event in
            switch lane {
            case .syncSnapshot:
                true
            case .widget, .liveActivity:
                switch event {
                case .taskChanged,
                     .ledgerChanged,
                     .pomodoroChanged,
                     .remoteImportCompleted,
                     .fullSync:
                    true
                case .preferenceChanged,
                     .checklistChanged,
                     .countdownChanged,
                     .inboxChanged:
                    false
                }
            case .watch:
                switch event {
                case .taskChanged,
                     .ledgerChanged,
                     .pomodoroChanged,
                     .preferenceChanged,
                     .remoteImportCompleted,
                     .fullSync:
                    true
                case .checklistChanged,
                     .countdownChanged,
                     .inboxChanged:
                    false
                }
            }
        }
    }
}
