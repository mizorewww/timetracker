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

    /// Executes a queued CloudKit reset without acknowledging it.
    ///
    /// The pending defaults remain set until a CloudKit container has been
    /// created successfully and `recordCloudKitEnabled(after:)` receives the
    /// completion token returned here. A deferred or failed recovery therefore
    /// cannot be mistaken for a reset that is safe to acknowledge.
    static func performPendingCloudRecoveryResetIfNeeded(
        canResetUpload: Bool = true,
        storeURL: URL? = nil,
        removeStoreFiles: (@MainActor (URL) throws -> Void)? = nil,
        removeSyncConflictState: (@MainActor () throws -> Void)? = nil,
        beginCloudImportSession: (@MainActor (CloudRecoveryImportKind) throws -> Void)? = nil
    ) -> CloudRecoveryGate {
        let defaults = AppDefaults.shared
        let shouldResetForDownload = defaults.bool(forKey: pendingCloudDownloadResetKey)
        let shouldResetForUpload = defaults.bool(forKey: pendingCloudUploadResetKey)
        let shouldMarkRecoveryStoreReset = shouldResetForUpload
        if shouldResetForDownload && shouldResetForUpload {
            logger.error("Refused conflicting CloudKit upload and download recovery requests")
            return .deferred(.conflictingRecoveryRequests)
        }
        guard shouldResetForDownload || shouldResetForUpload else {
            return .completed(CompletedCloudRecovery(reset: .none))
        }
        guard shouldResetForDownload || canResetUpload else {
            logger.error("Skipped CloudKit upload recovery reset because no protected upload snapshot was found")
            return .deferred(.protectedUploadSnapshotUnavailable)
        }

        let resolvedStoreURL = storeURL ?? persistentStoreURL
        let storeFileRemover: @MainActor (URL) throws -> Void
        if let removeStoreFiles {
            storeFileRemover = removeStoreFiles
        } else {
            storeFileRemover = { url in
                try removePersistentStoreFiles(at: url)
            }
        }
        let scope = TimerStoreScope(persistentStoreURL: resolvedStoreURL)
        do {
            try FileManager.default.createDirectory(
                at: resolvedStoreURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            return try StoreScopedTimerMutationLock().withExclusiveAccess(
                for: scope
            ) {
                performPendingCloudRecoveryResetWithLockedStore(
                    shouldResetForDownload: shouldResetForDownload,
                    shouldMarkRecoveryStoreReset: shouldMarkRecoveryStoreReset,
                    storeURL: resolvedStoreURL,
                    storeFileRemover: storeFileRemover,
                    removeSyncConflictState: removeSyncConflictState,
                    beginCloudImportSession: beginCloudImportSession
                )
            }
        } catch {
            logger.error(
                "CloudKit recovery could not lock or remove persistent store files: \(error.localizedDescription, privacy: .public)"
            )
            return .failed(
                CloudRecoveryFailure(stage: .persistentStoreRemoval, underlyingError: error)
            )
        }
    }

    private static func performPendingCloudRecoveryResetWithLockedStore(
        shouldResetForDownload: Bool,
        shouldMarkRecoveryStoreReset: Bool,
        storeURL: URL,
        storeFileRemover: @MainActor (URL) throws -> Void,
        removeSyncConflictState: (@MainActor () throws -> Void)?,
        beginCloudImportSession: (@MainActor (CloudRecoveryImportKind) throws -> Void)?
    ) -> CloudRecoveryGate {
        if shouldMarkRecoveryStoreReset {
            AppDefaults.shared.set(true, forKey: cloudRecoveryStoreResetKey)
        }
        do {
            let durableRoot = storeURL.deletingLastPathComponent()
            let localFile = DurableLocalFile()
            try localFile.withExclusiveAccess(through: durableRoot) {
                try PersistentHistoryProjectionResetFence(
                    scope: TimerStoreScope(
                        persistentStoreURL: storeURL
                    ),
                    localFile: localFile
                ).advanceForStoreReset()
                try storeFileRemover(storeURL)
            }
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
            let stateRemover: @MainActor () throws -> Void
            if let removeSyncConflictState {
                stateRemover = removeSyncConflictState
            } else {
                stateRemover = {
                    try SyncConflictService.removeDefaultState()
                }
            }
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

        let importKind: CloudRecoveryImportKind? = if reset == .download {
            .downloadCloud
        } else if AppDefaults.shared.bool(forKey: queuedCloudReconciliationKey) {
            .reconcileWithCloud
        } else {
            nil
        }
        if let importKind {
            let sessionStarter = beginCloudImportSession ?? { kind in
                try SyncConflictService().beginCloudRecoveryImportSession(kind: kind)
            }
            do {
                try sessionStarter(importKind)
            } catch {
                logger.error(
                    "CloudKit recovery could not persist its initial import session: \(error.localizedDescription, privacy: .public)"
                )
                return .failed(
                    CloudRecoveryFailure(
                        stage: .syncConflictStatePreparation,
                        underlyingError: error
                    )
                )
            }
        }

        return .completed(CompletedCloudRecovery(reset: reset))
    }

    static func checkAccountStatus(
        client: CloudAccountStatusClient? = nil,
        checkedAt: Date = Date()
    ) async -> CloudAccountCheckOutcome {
        let resolvedClient: CloudAccountStatusClient = if let client {
            client
        } else {
            .live(containerIdentifier: containerIdentifier)
        }
        let result: CloudAccountCheckResult
        do {
            let status = try await resolvedClient.fetchStatus()
            switch status {
            case .available:
                result = .available
            case .noAccount:
                result = .unavailable(.noAccount)
            case .restricted:
                result = .unavailable(.restricted)
            case .couldNotDetermine:
                result = .unavailable(.couldNotDetermine)
            case .temporarilyUnavailable:
                result = .unavailable(.temporarilyUnavailable)
            @unknown default:
                result = .unavailable(.unknown)
            }
        } catch {
            result = .failed(message: error.localizedDescription)
        }
        logger.info("CloudKit account check completed: \(String(describing: result), privacy: .public)")
        return CloudAccountCheckOutcome(checkedAt: checkedAt, result: result)
    }

    private static func removePersistentStoreFiles(at storeURL: URL) throws {
        let fileManager = FileManager.default
        let directory = storeURL.deletingLastPathComponent()
        guard fileManager.fileExists(atPath: directory.path) else { return }

        let localFile = DurableLocalFile()
        try localFile.withExclusiveAccess(through: directory) {
            let storePrefix = storeURL.lastPathComponent
            let storeFiles = try fileManager.contentsOfDirectory(
                at: directory,
                includingPropertiesForKeys: nil
            )
            .filter {
                $0.lastPathComponent.hasPrefix(storePrefix) &&
                    $0.lastPathComponent
                    != storePrefix
                    + StoreScopedTimerMutationLock.fileSuffix
            }

            for file in storeFiles {
                try localFile.removeIfPresent(
                    at: file,
                    durableRootURL: directory
                )
            }
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
        case conflictingRecoveryRequests

        var errorDescription: String? {
            switch self {
            case .protectedUploadSnapshotUnavailable:
                AppStrings.localized("sync.recovery.deferred.uploadSnapshotUnavailable")
            case .conflictingRecoveryRequests:
                AppStrings.localized("sync.recovery.deferred.conflictingRequests")
            }
        }
    }

    struct CloudRecoveryFailure: LocalizedError {
        enum Stage: Equatable {
            case persistentStoreRemoval
            case syncConflictStateRemoval
            case syncConflictStatePreparation
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
            case .syncConflictStatePreparation:
                String(
                    format: AppStrings.localized("sync.recovery.error.statePreparation"),
                    underlyingError.localizedDescription
                )
            }
        }
    }
}
