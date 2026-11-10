import Foundation

extension TimeTrackerStore {
    /// One finished CloudKit event or remote-store change, reported to the
    /// user as the latest Cloud activity.
    enum SyncRefreshReason: Sendable {
        case remoteStoreChanged
        case cloudImportFinished(succeeded: Bool, failureMessage: String?)
        case cloudExportFinished(succeeded: Bool, failureMessage: String?)
        case cloudSetupFinished(succeeded: Bool, failureMessage: String?)

        /// Failures outrank successes, and an import outranks an export or
        /// setup, when several events land in one coalescing window.
        var priority: Int {
            switch self {
            case .remoteStoreChanged:
                0
            case let .cloudExportFinished(succeeded, _), let .cloudSetupFinished(succeeded, _):
                succeeded ? 1 : 3
            case let .cloudImportFinished(succeeded, _):
                succeeded ? 2 : 3
            }
        }

        func activityOutcome(
            completedAt: Date,
            processingFailureMessage: String? = nil
        ) -> SyncActivityOutcome? {
            let kind: SyncActivityKind
            let succeeded: Bool
            let failureMessage: String?
            switch self {
            case .remoteStoreChanged:
                guard let processingFailureMessage else { return nil }
                return SyncActivityOutcome(
                    kind: .remoteRefresh,
                    completedAt: completedAt,
                    result: .failed(message: processingFailureMessage)
                )
            case let .cloudImportFinished(eventSucceeded, message):
                (kind, succeeded, failureMessage) = (.importData, eventSucceeded, message)
            case let .cloudExportFinished(eventSucceeded, message):
                (kind, succeeded, failureMessage) = (.exportData, eventSucceeded, message)
            case let .cloudSetupFinished(eventSucceeded, message):
                (kind, succeeded, failureMessage) = (.setup, eventSucceeded, message)
            }
            let result: SyncActivityResult = if let processingFailureMessage {
                .failed(message: processingFailureMessage)
            } else if succeeded {
                .succeeded
            } else {
                .failed(message: failureMessage ?? AppStrings.localized("sync.activity.unknownFailure"))
            }
            return SyncActivityOutcome(kind: kind, completedAt: completedAt, result: result)
        }
    }

    private static let syncRefreshCoalescingDelay: Duration = .milliseconds(350)

    /// Persistent history narrows the catch-up to the models that changed;
    /// a window with no new transactions (an export or setup event) refreshes
    /// nothing.
    private func remoteChangeRefreshPlan() -> StoreRefreshPlan {
        guard let modelContext else {
            return StoreRefreshPlanner.plan(after: [.remoteImportCompleted])
        }
        return remoteChangeHistory.refreshPlanSinceLastCatchUp(in: modelContext)
    }

    /// Coalesces CloudKit and remote-store notifications into one read-model
    /// catch-up per window; the window's highest-priority event becomes the
    /// reported Cloud activity.
    func scheduleQuietRefresh(reason: SyncRefreshReason) {
        if pendingSyncActivityReason.map({ reason.priority >= $0.priority }) ?? true {
            pendingSyncActivityReason = reason
        }
        guard scheduledSyncRefreshTask == nil else { return }
        scheduledSyncRefreshTask = Task { @MainActor [weak self] in
            do {
                try await Task.sleep(for: Self.syncRefreshCoalescingDelay)
            } catch {
                return
            }
            guard let self else { return }
            scheduledSyncRefreshTask = nil
            let activityReason = pendingSyncActivityReason
            pendingSyncActivityReason = nil
            var processingFailureMessage: String?
            let plan = remoteChangeRefreshPlan()
            if plan.scopes.isEmpty == false {
                do {
                    if hasCompletedStartupConfiguration {
                        try refresh(plan: plan)
                    } else {
                        try StoreRefreshCoordinator.refreshReadModels(self, plan: plan)
                    }
                } catch {
                    processingFailureMessage = error.localizedDescription
                }
                enqueueCommittedMutationSystemProjections(
                    events: [.remoteImportCompleted]
                )
            }
            if let outcome = activityReason?.activityOutcome(
                completedAt: Date(),
                processingFailureMessage: processingFailureMessage
            ) {
                lastSyncActivity = outcome
            }
        }
    }
}
