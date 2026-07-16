import CloudKit
import Foundation
import OSLog
import SwiftData

extension AppCloudSync {
    static var persistentStoreURL: URL {
        ModelConfiguration(
            "TimeTracker",
            schema: nil,
            isStoredInMemoryOnly: false,
            cloudKitDatabase: .none
        ).url
    }

    static func requestCloudRetryAfterRecovery() {
        AppDemoDataConfiguration.disableLocalDemoStoreForCloudSync()
        UserDefaults.standard.set(true, forKey: enabledKey)
        UserDefaults.standard.removeObject(forKey: errorKey)
    }

    static func requestCloudUploadReset() {
        UserDefaults.standard.set(true, forKey: pendingCloudUploadResetKey)
        requestCloudRetryAfterRecovery()
        logger.warning("Queued CloudKit upload recovery reset")
    }

    static func requestCloudDownloadReset() {
        UserDefaults.standard.set(true, forKey: pendingCloudDownloadResetKey)
        requestCloudRetryAfterRecovery()
        logger.warning("Queued CloudKit download recovery reset")
    }

    /// Executes a queued CloudKit reset without acknowledging it.
    ///
    /// The pending defaults remain set until a CloudKit container has been
    /// created successfully and `recordCloudKitEnabled(after:)` receives the
    /// completion token returned here. A deferred or failed recovery therefore
    /// cannot be mistaken for a reset that is safe to acknowledge.
    static func performPendingCloudRecoveryResetIfNeeded(
        canResetUpload: Bool = true,
        storeURL: URL? = nil,
        removeStoreFiles: ((URL) throws -> Void)? = nil,
        removeSyncConflictState: (() throws -> Void)? = nil
    ) -> CloudRecoveryGate {
        let defaults = UserDefaults.standard
        let shouldResetForDownload = defaults.bool(forKey: pendingCloudDownloadResetKey)
        let shouldResetForUpload = defaults.bool(forKey: pendingCloudUploadResetKey)
        guard shouldResetForDownload || shouldResetForUpload else {
            return .completed(CompletedCloudRecovery(reset: .none))
        }
        guard shouldResetForDownload || canResetUpload else {
            logger.error("Skipped CloudKit upload recovery reset because no protected upload snapshot was found")
            return .deferred(.protectedUploadSnapshotUnavailable)
        }

        let resolvedStoreURL = storeURL ?? persistentStoreURL
        let storeFileRemover = removeStoreFiles ?? removePersistentStoreFiles
        do {
            try storeFileRemover(resolvedStoreURL)
        } catch {
            logger.error(
                "CloudKit recovery could not remove persistent store files: \(error.localizedDescription, privacy: .public)"
            )
            return .failed(
                CloudRecoveryFailure(stage: .persistentStoreRemoval, underlyingError: error)
            )
        }

        let reset: CloudRecoveryReset = shouldResetForDownload ? .download : .upload
        logger.warning(
            "Removed persistent store files for CloudKit recovery reset: \(shouldResetForDownload ? "download" : "upload", privacy: .public)"
        )

        if reset == .download {
            let stateRemover = removeSyncConflictState ?? SyncConflictService.removeDefaultState
            do {
                try stateRemover()
            } catch {
                logger.error(
                    "CloudKit download recovery could not remove sync conflict state: \(error.localizedDescription, privacy: .public)"
                )
                return .failed(
                    CloudRecoveryFailure(stage: .syncConflictStateRemoval, underlyingError: error)
                )
            }
        }

        return .completed(CompletedCloudRecovery(reset: reset))
    }

    static func refreshAccountStatus() async {
        let container = CKContainer(identifier: containerIdentifier)
        let statusText: String
        do {
            let status = try await container.accountStatus()
            switch status {
            case .available:
                statusText = AppStrings.localized("sync.account.available")
            case .noAccount:
                statusText = AppStrings.localized("sync.account.noAccount")
            case .restricted:
                statusText = AppStrings.localized("sync.account.restricted")
            case .couldNotDetermine:
                statusText = AppStrings.localized("sync.account.couldNotDetermine")
            case .temporarilyUnavailable:
                statusText = AppStrings.localized("sync.account.temporarilyUnavailable")
            @unknown default:
                statusText = AppStrings.localized("sync.account.unknown")
            }
        } catch {
            statusText = error.localizedDescription
        }
        UserDefaults.standard.set(statusText, forKey: accountStatusKey)
        logger.info("CloudKit account status: \(statusText, privacy: .public)")
    }

    private static func removePersistentStoreFiles(at storeURL: URL) throws {
        let fileManager = FileManager.default
        let directory = storeURL.deletingLastPathComponent()
        guard fileManager.fileExists(atPath: directory.path) else { return }

        let storePrefix = storeURL.lastPathComponent
        let storeFiles = try fileManager.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil
        )
        .filter { $0.lastPathComponent.hasPrefix(storePrefix) }

        for file in storeFiles {
            try fileManager.removeItem(at: file)
        }
    }

    enum CloudRecoveryReset: Equatable {
        case none
        case upload
        case download
    }

    struct CompletedCloudRecovery {
        let reset: CloudRecoveryReset

        fileprivate init(reset: CloudRecoveryReset) {
            self.reset = reset
        }
    }

    enum CloudRecoveryGate {
        case completed(CompletedCloudRecovery)
        case deferred(CloudRecoveryDeferral)
        case failed(CloudRecoveryFailure)
    }

    enum CloudRecoveryDeferral: LocalizedError, Equatable {
        case protectedUploadSnapshotUnavailable

        var errorDescription: String? {
            switch self {
            case .protectedUploadSnapshotUnavailable:
                AppStrings.localized("sync.recovery.deferred.uploadSnapshotUnavailable")
            }
        }
    }

    struct CloudRecoveryFailure: LocalizedError {
        enum Stage: Equatable {
            case persistentStoreRemoval
            case syncConflictStateRemoval
        }

        let stage: Stage
        let underlyingError: Error

        var errorDescription: String? {
            switch stage {
            case .persistentStoreRemoval:
                String(
                    format: AppStrings.localized("sync.recovery.error.storeRemoval"),
                    underlyingError.localizedDescription
                )
            case .syncConflictStateRemoval:
                String(
                    format: AppStrings.localized("sync.recovery.error.stateRemoval"),
                    underlyingError.localizedDescription
                )
            }
        }
    }
}
