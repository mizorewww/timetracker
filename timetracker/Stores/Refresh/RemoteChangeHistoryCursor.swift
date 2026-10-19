import Foundation
import SwiftData

/// Reads persistent history since the previous remote catch-up so a CloudKit
/// import or another process's commit refreshes only the read models whose
/// models actually changed. This process's own store mutations are skipped:
/// every scene in the process already refreshed through the mutating store or
/// `StoreMutationBroadcaster`.
@MainActor
final class RemoteChangeHistoryCursor {
    private var lastToken: DefaultHistoryToken?
    private var baselineDate: Date

    /// `baselineDate` must not be later than the startup full refresh; the
    /// store creates its cursor before configuring, so that holds.
    init(baselineDate: Date = Date()) {
        self.baselineDate = baselineDate
    }

    /// Refresh scopes touched since the previous call. Unreadable history
    /// (for example an expired token) falls back to a full refresh and
    /// restarts the cursor from now.
    func scopesSinceLastCatchUp(in context: ModelContext) -> Set<StoreRefreshScope> {
        let descriptor: HistoryDescriptor<DefaultHistoryTransaction>
        if let lastToken {
            descriptor = HistoryDescriptor(predicate: #Predicate { $0.token > lastToken })
        } else {
            let baselineDate = baselineDate
            descriptor = HistoryDescriptor(predicate: #Predicate { $0.timestamp >= baselineDate })
        }

        let transactions: [DefaultHistoryTransaction]
        do {
            transactions = try context.fetchHistory(descriptor)
        } catch {
            lastToken = nil
            baselineDate = Date()
            return StoreRefreshScope.full
        }
        if let newestToken = transactions.map(\.token).max() {
            lastToken = newestToken
        }
        let ownAuthor = TimeTrackerHistoryAuthor.localMutation.transactionAuthor
        let entityNames = Set(
            transactions.lazy
                .filter { $0.author != ownAuthor }
                .flatMap(\.changes)
                .map(\.changedPersistentIdentifier.entityName)
        )
        return Self.scopes(forChangedEntityNames: entityNames)
    }

    static func scopes(forChangedEntityNames entityNames: Set<String>) -> Set<StoreRefreshScope> {
        entityNames.reduce(into: Set<StoreRefreshScope>()) { result, entityName in
            result.formUnion(scopesByEntityName[entityName] ?? StoreRefreshScope.full)
        }
    }

    /// Mirrors `StoreRefreshPlanner.plan(after:)` scopes for the domain event each
    /// model's commands publish. A model missing here refreshes everything.
    private static let scopesByEntityName: [String: Set<StoreRefreshScope>] = {
        let task: Set<StoreRefreshScope> = [.tasks, .rollups, .analytics]
        let ledger: Set<StoreRefreshScope> = [
            .ledgerVisible, .ledgerHistory, .pomodoro, .rollups, .analytics,
        ]
        let pomodoro: Set<StoreRefreshScope> = [.ledgerVisible, .pomodoro, .rollups, .analytics]
        let checklist: Set<StoreRefreshScope> = [.checklist, .rollups, .analytics]
        let entries: [(any PersistentModel.Type, Set<StoreRefreshScope>)] = [
            (TaskNode.self, task),
            (TaskCategory.self, task),
            (TaskCategoryAssignment.self, task),
            (TaskRecurrenceRule.self, task),
            (TaskRecurrenceOccurrence.self, task),
            (TaskQuantityGoal.self, task),
            (TaskQuantityEntry.self, task),
            (TimeSession.self, ledger),
            (TimeSegment.self, ledger),
            (PomodoroRun.self, pomodoro),
            (ChecklistItem.self, checklist),
            (ChecklistItemVisual.self, checklist),
            (InboxItem.self, [.inbox]),
            (InboxSuggestion.self, [.inbox]),
            (InboxCaptureReceipt.self, [.inbox]),
            (SyncedPreference.self, [.preferences]),
            (CountdownEvent.self, [.countdown]),
        ]
        var scopesByEntityName: [String: Set<StoreRefreshScope>] = [:]
        for (model, scopes) in entries {
            scopesByEntityName[entityName(of: model)] = scopes
        }
        return scopesByEntityName
    }()

    static func entityName<Model: PersistentModel>(of model: Model.Type) -> String {
        Schema.entityName(for: model)
    }
}
