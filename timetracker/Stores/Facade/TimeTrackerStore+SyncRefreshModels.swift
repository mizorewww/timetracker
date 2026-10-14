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
}
