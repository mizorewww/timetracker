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

    @discardableResult
    static func performPendingCloudRecoveryResetIfNeeded(
        canResetUpload: Bool = true
    ) throws -> CloudRecoveryReset {
        let defaults = UserDefaults.standard
        let shouldResetForDownload = defaults.bool(forKey: pendingCloudDownloadResetKey)
        let shouldResetForUpload = defaults.bool(forKey: pendingCloudUploadResetKey)
        guard shouldResetForDownload || shouldResetForUpload else {
            return .none
        }
        guard shouldResetForDownload || canResetUpload else {
            logger.error("Skipped CloudKit upload recovery reset because no protected upload snapshot was found")
            return .none
        }
        try removePersistentStoreFiles(at: persistentStoreURL)
        logger.warning(
            "Removed persistent store files for CloudKit recovery reset: \(shouldResetForDownload ? "download" : "upload", privacy: .public)"
        )
        return shouldResetForDownload ? .download : .upload
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

    enum CloudRecoveryReset {
        case none
        case upload
        case download
    }
}
