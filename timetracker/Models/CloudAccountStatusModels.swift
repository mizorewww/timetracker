import CloudKit
import Foundation

nonisolated struct CloudAccountStatusClient: Sendable {
    let fetchStatus: @Sendable () async throws -> CKAccountStatus

    static func live(containerIdentifier: String) -> Self {
        Self {
            try await CKContainer(identifier: containerIdentifier).accountStatus()
        }
    }
}

nonisolated enum CloudAccountUnavailableReason: Equatable, Sendable {
    case noAccount
    case restricted
    case couldNotDetermine
    case temporarilyUnavailable
    case unknown

    @MainActor
    var localizedDescription: String {
        switch self {
        case .noAccount:
            AppStrings.localized("sync.account.noAccount")
        case .restricted:
            AppStrings.localized("sync.account.restricted")
        case .couldNotDetermine:
            AppStrings.localized("sync.account.couldNotDetermine")
        case .temporarilyUnavailable:
            AppStrings.localized("sync.account.temporarilyUnavailable")
        case .unknown:
            AppStrings.localized("sync.account.unknown")
        }
    }
}

nonisolated enum CloudAccountCheckResult: Equatable, Sendable {
    case available
    case unavailable(CloudAccountUnavailableReason)
    case failed(message: String)

    @MainActor
    var localizedDescription: String {
        switch self {
        case .available:
            AppStrings.localized("sync.account.available")
        case let .unavailable(reason):
            reason.localizedDescription
        case let .failed(message):
            message
        }
    }
}

nonisolated struct CloudAccountCheckOutcome: Equatable, Sendable {
    let checkedAt: Date
    let result: CloudAccountCheckResult
}
