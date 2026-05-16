import Foundation

struct SyncStatus {
    let mode: String
    let containerIdentifier: String
    let deviceID: String
    let lastError: String?
    let accountStatus: String

    var isCloudBacked: Bool {
        mode == "iCloud"
    }

    var storageStatusText: String {
        switch mode {
        case AppCloudSync.modeICloud:
            return AppStrings.localized("sync.storage.iCloud")
        case AppCloudSync.modeLocal:
            return AppStrings.localized("sync.storage.local")
        case AppCloudSync.modeLocalFallback:
            return AppStrings.localized("sync.storage.localFallback")
        case AppCloudSync.modeInMemoryFallback:
            return AppStrings.localized("sync.storage.temporary")
        case AppCloudSync.modeUITest:
            return AppStrings.localized("sync.storage.uiTest")
        default:
            return mode
        }
    }

    func feedback(
        preferences: AppPreferences,
        isChecking: Bool,
        lastRefreshAt: Date?,
        now: Date = Date()
    ) -> SyncFeedback {
        if isChecking {
            return SyncFeedback(
                state: .syncing,
                title: AppStrings.localized("sync.state.syncing.title"),
                message: AppStrings.localized("sync.state.syncing.message")
            )
        }

        if mode == AppCloudSync.modeInMemoryFallback {
            return SyncFeedback(
                state: .temporaryStore,
                title: AppStrings.localized("sync.state.temporary.title"),
                message: String(
                    format: AppStrings.localized("sync.state.temporary.message"),
                    storageStatusText,
                    lastError?.isEmpty == false ? lastError! : accountStatus
                )
            )
        }

        if let lastError, !lastError.isEmpty {
            return SyncFeedback(
                state: .failed,
                title: AppStrings.localized("sync.state.failed.title"),
                message: String(format: AppStrings.localized("sync.state.failed.message"), lastError)
            )
        }

        if preferences.cloudSyncEnabled != isCloudBacked {
            return SyncFeedback(
                state: .needsRestart,
                title: AppStrings.localized("sync.state.needsRestart.title"),
                message: AppStrings.localized("sync.state.needsRestart.message")
            )
        }

        if !preferences.cloudSyncEnabled {
            return SyncFeedback(
                state: .localOnly,
                title: AppStrings.localized("sync.state.localOnly.title"),
                message: AppStrings.localized("sync.state.localOnly.message")
            )
        }

        if let lastRefreshAt, now.timeIntervalSince(lastRefreshAt) <= 120 {
            let time = DateFormatter.localizedString(from: lastRefreshAt, dateStyle: .none, timeStyle: .short)
            return SyncFeedback(
                state: .recentlySynced,
                title: AppStrings.localized("sync.state.recent.title"),
                message: String(format: AppStrings.localized("sync.state.recent.message"), time)
            )
        }

        if isCloudBacked {
            return SyncFeedback(
                state: .available,
                title: AppStrings.localized("sync.state.available.title"),
                message: String(format: AppStrings.localized("sync.state.available.message"), accountStatus)
            )
        }

        return SyncFeedback(
            state: .offline,
            title: AppStrings.localized("sync.state.offline.title"),
            message: String(format: AppStrings.localized("sync.state.offline.message"), accountStatus)
        )
    }
}

enum SyncFeedbackState: Equatable {
    case available
    case syncing
    case recentlySynced
    case offline
    case needsRestart
    case failed
    case localOnly
    case temporaryStore
    case conflict

    var symbolName: String {
        switch self {
        case .available:
            return "icloud"
        case .syncing:
            return "arrow.triangle.2.circlepath.icloud"
        case .recentlySynced:
            return "checkmark.icloud"
        case .offline:
            return "icloud.slash"
        case .needsRestart:
            return "arrow.clockwise.circle"
        case .failed:
            return "exclamationmark.icloud"
        case .localOnly:
            return "externaldrive"
        case .temporaryStore:
            return "externaldrive.badge.exclamationmark"
        case .conflict:
            return "exclamationmark.triangle"
        }
    }
}

struct SyncFeedback: Equatable {
    let state: SyncFeedbackState
    let title: String
    let message: String
}
