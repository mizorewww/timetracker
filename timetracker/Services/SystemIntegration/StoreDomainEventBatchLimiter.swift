import Foundation

/// Keeps deferred event batches bounded without losing convergence. Consumers
/// materialize current committed facts, so an oversized precise batch can
/// safely become one full refresh.
nonisolated enum StoreDomainEventBatchLimiter {
    static let defaultRetentionCostLimit = 512

    static func bounded(
        _ events: Set<StoreDomainEvent>,
        retentionCostLimit: Int = defaultRetentionCostLimit
    ) -> Set<StoreDomainEvent> {
        guard events.isEmpty == false else { return [] }
        guard events.contains(.fullSync) == false else { return [.fullSync] }

        var remainingCost = max(0, retentionCostLimit)
        for event in events {
            guard consume(1, from: &remainingCost),
                  consumeAssociatedValues(
                      in: event,
                      from: &remainingCost
                  )
            else {
                return [.fullSync]
            }
        }
        return events
    }

    private static func consumeAssociatedValues(
        in event: StoreDomainEvent,
        from remainingCost: inout Int
    ) -> Bool {
        switch event {
        case let .taskChanged(taskID, affectedAncestorIDs),
             let .checklistChanged(taskID, affectedAncestorIDs):
            return consume(taskID == nil ? 0 : 1, from: &remainingCost)
                && consume(
                    affectedAncestorIDs.count,
                    from: &remainingCost
                )
        case let .ledgerChanged(taskID, dateInterval, _):
            return consume(taskID == nil ? 0 : 1, from: &remainingCost)
                && consume(dateInterval == nil ? 0 : 1, from: &remainingCost)
        case let .pomodoroChanged(runID, sessionID, taskID):
            return consume(runID == nil ? 0 : 1, from: &remainingCost)
                && consume(sessionID == nil ? 0 : 1, from: &remainingCost)
                && consume(taskID == nil ? 0 : 1, from: &remainingCost)
        case let .preferenceChanged(key):
            guard let key else { return true }
            let boundedByteCount = key.utf8.prefix(remainingCost + 1).count
            return consume(boundedByteCount, from: &remainingCost)
        case let .inboxChanged(itemIDs):
            return consume(itemIDs.count, from: &remainingCost)
        case .countdownChanged,
             .remoteImportCompleted,
             .fullSync:
            return true
        }
    }

    private static func consume(
        _ cost: Int,
        from remainingCost: inout Int
    ) -> Bool {
        guard cost <= remainingCost else { return false }
        remainingCost -= cost
        return true
    }
}
