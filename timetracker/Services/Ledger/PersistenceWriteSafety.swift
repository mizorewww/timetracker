import Foundation

enum PersistenceWriteSafety: Equatable {
    case ready
    case cloudRecoveryPending(String?)
    case ephemeral(String?)

    var title: String {
        switch self {
        case .ready:
            ""
        case .cloudRecoveryPending:
            AppStrings.localized("persistence.recovery.title")
        case .ephemeral:
            AppStrings.localized("persistence.ephemeral.title")
        }
    }

    var message: String {
        switch self {
        case .ready:
            ""
        case let .cloudRecoveryPending(detail):
            Self.message(
                key: "persistence.recovery.message",
                detail: detail
            )
        case let .ephemeral(detail):
            Self.message(
                key: "persistence.ephemeral.message",
                detail: detail
            )
        }
    }

    var symbolName: String {
        switch self {
        case .ready:
            "checkmark.circle"
        case .cloudRecoveryPending:
            "arrow.triangle.2.circlepath.icloud"
        case .ephemeral:
            "externaldrive.badge.exclamationmark"
        }
    }

    func diagnosticReport(persistenceMode: String, storeURL: URL) -> String {
        String(
            format: AppStrings.localized("persistence.diagnostics.format"),
            title,
            message,
            persistenceMode,
            storeURL.path
        )
    }

    private static func message(key: String, detail: String?) -> String {
        let safeDetail = detail?.trimmingCharacters(in: .whitespacesAndNewlines)
        return String(
            format: AppStrings.localized(key),
            safeDetail?.isEmpty == false ? safeDetail! : AppStrings.localized("persistence.error.noDetails")
        )
    }
}

enum PersistenceWriteError: LocalizedError, Equatable {
    case blocked(String)

    var errorDescription: String? {
        switch self {
        case let .blocked(message):
            message
        }
    }
}
