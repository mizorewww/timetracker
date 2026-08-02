import SwiftData

nonisolated enum TimeTrackerHistoryAuthor: String, Sendable {
    case localMutation = "me.mezorewww.timetracker.local-mutation.v1"
    case syncReconciliation = "me.mezorewww.timetracker.sync-reconciliation.v1"
    case bootstrapMaintenance = "me.mezorewww.timetracker.bootstrap-maintenance.v1"
}

private nonisolated enum ModelContextMutationState {
    @TaskLocal static var contextStack: [ObjectIdentifier] = []
}

nonisolated extension ModelContext {
    /// Temporarily attributes every save in this scope to one stable history
    /// source, then restores the caller's author even when the operation throws.
    func withHistoryAuthor<Result>(
        _ historyAuthor: TimeTrackerHistoryAuthor,
        _ operation: () throws -> Result
    ) rethrows -> Result {
        let previousAuthor = author
        author = historyAuthor.rawValue
        defer { author = previousAuthor }
        return try operation()
    }

    /// Saves immediately for standalone repository calls, but defers nested
    /// command saves while a store-level mutation is being committed atomically.
    func saveAfterMutationStep() throws {
        guard ModelContextMutationState.contextStack.contains(
            ObjectIdentifier(self)
        ) == false else {
            return
        }
        do {
            try save()
        } catch {
            rollback()
            throw error
        }
    }

    /// Commits all nested repository and command changes with one final save.
    /// A thrown command or final save failure rolls back the complete unit of work.
    func performAtomicMutation<Result>(_ action: () throws -> Result) throws -> Result {
        let identifier = ObjectIdentifier(self)
        let isOutermost = ModelContextMutationState.contextStack.contains(
            identifier
        ) == false
        guard isOutermost else { return try action() }

        return try ModelContextMutationState.$contextStack.withValue(
            ModelContextMutationState.contextStack + [identifier]
        ) {
            do {
                let result = try action()
                try save()
                return result
            } catch {
                rollback()
                throw error
            }
        }
    }

    /// Commits one atomic mutation with an explicit persistent-history source.
    func performAtomicMutation<Result>(
        author historyAuthor: TimeTrackerHistoryAuthor,
        _ action: () throws -> Result
    ) throws -> Result {
        try withHistoryAuthor(historyAuthor) {
            try performAtomicMutation(action)
        }
    }
}
