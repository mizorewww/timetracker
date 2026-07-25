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
                0
            case let .cloudExportFinished(_, succeeded, reportsConflict, _):
                reportsConflict ? 4 : (succeeded ? 1 : 3)
            case let .cloudImportFinished(succeeded, reportsConflict, _):
                reportsConflict ? 4 : (succeeded ? 2 : 3)
            case let .cloudSetupFinished(succeeded, _):
                succeeded ? 1 : 3
            }
        }

        var activityKind: SyncActivityKind {
            switch self {
            case .remoteStoreChanged:
                .remoteRefresh
            case .cloudImportFinished:
                .importData
            case .cloudExportFinished:
                .exportData
            case .cloudSetupFinished:
                .setup
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
        private(set) var activityReason: SyncRefreshReason?
        private(set) var requiresCloudImportHandling = false
        private var latestCloudImportSucceeded: Bool?

        mutating func insert(_ reason: SyncRefreshReason) {
            if activityReason.map({ reason.priority >= $0.priority }) ?? true {
                activityReason = reason
            }
            switch reason {
            case let .cloudImportFinished(succeeded, reportsConflict, _):
                latestCloudImportSucceeded = succeeded
                requiresCloudImportHandling = requiresCloudImportHandling
                    || succeeded
                    || reportsConflict
            case let .cloudExportFinished(_, _, reportsConflict, _):
                requiresCloudImportHandling = requiresCloudImportHandling || reportsConflict
            case .remoteStoreChanged, .cloudSetupFinished:
                break
            }
        }

        var hasSuccessfulCloudImport: Bool {
            latestCloudImportSucceeded == true
        }
    }
}
