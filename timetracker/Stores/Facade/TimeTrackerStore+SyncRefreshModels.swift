import Foundation

extension TimeTrackerStore {
    enum SyncRefreshReason: Sendable {
        case remoteStoreChanged
        case cloudImportFinished(
            succeeded: Bool,
            reportsConflict: Bool,
            failureMessage: String?
        )
        case cloudExportFinished(
            eventID: UUID,
            succeeded: Bool,
            reportsConflict: Bool,
            failureMessage: String?
        )
        case cloudSetupFinished(succeeded: Bool, failureMessage: String?)

        var priority: Int {
            switch self {
            case .remoteStoreChanged:
                return 0
            case let .cloudExportFinished(_, succeeded, reportsConflict, _):
                return reportsConflict ? 4 : (succeeded ? 1 : 3)
            case let .cloudImportFinished(succeeded, reportsConflict, _):
                return reportsConflict ? 4 : (succeeded ? 2 : 3)
            case let .cloudSetupFinished(succeeded, _):
                return succeeded ? 1 : 3
            }
        }

        var activityKind: SyncActivityKind {
            switch self {
            case .remoteStoreChanged:
                return .remoteRefresh
            case .cloudImportFinished:
                return .importData
            case .cloudExportFinished:
                return .exportData
            case .cloudSetupFinished:
                return .setup
            }
        }

        func activityOutcome(
            completedAt: Date,
            processingFailureMessage: String? = nil
        ) -> SyncActivityOutcome? {
            if let processingFailureMessage {
                return SyncActivityOutcome(
                    kind: activityKind,
                    completedAt: completedAt,
                    result: .failed(message: processingFailureMessage)
                )
            }
            switch self {
            case .remoteStoreChanged:
                return nil
            case let .cloudImportFinished(succeeded, _, failureMessage),
                 let .cloudSetupFinished(succeeded, failureMessage):
                return eventOutcome(
                    succeeded: succeeded,
                    failureMessage: failureMessage,
                    completedAt: completedAt
                )
            case let .cloudExportFinished(_, succeeded, _, failureMessage):
                return eventOutcome(
                    succeeded: succeeded,
                    failureMessage: failureMessage,
                    completedAt: completedAt
                )
            }
        }

        private func eventOutcome(
            succeeded: Bool,
            failureMessage: String?,
            completedAt: Date
        ) -> SyncActivityOutcome {
            let result: SyncActivityResult = succeeded
                ? .succeeded
                : .failed(
                    message: failureMessage
                        ?? AppStrings.localized("sync.activity.unknownFailure")
                )
            return SyncActivityOutcome(
                kind: activityKind,
                completedAt: completedAt,
                result: result
            )
        }
    }

    struct SyncRefreshBatch: Sendable {
        private(set) var reasons: [SyncRefreshReason] = []

        mutating func insert(_ reason: SyncRefreshReason) {
            reasons.append(reason)
        }

        var activityReason: SyncRefreshReason? {
            reasons.max { lhs, rhs in lhs.priority < rhs.priority }
        }

        var requiresCloudImportHandling: Bool {
            reasons.contains { reason in
                switch reason {
                case let .cloudImportFinished(succeeded, reportsConflict, _):
                    return succeeded || reportsConflict
                case let .cloudExportFinished(_, _, reportsConflict, _):
                    return reportsConflict
                case .remoteStoreChanged, .cloudSetupFinished:
                    return false
                }
            }
        }
    }
}
