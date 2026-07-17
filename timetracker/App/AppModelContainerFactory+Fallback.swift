import Foundation
import SwiftData

extension timetrackerApp {
    /// One outer store lock covers the final local snapshot and destructive
    /// recovery reset. Both nested operations intentionally reacquire the same
    /// recursive path lock; no other process can commit between them.
    static func performPendingCloudRecoveryResetAfterProtectingLocalFallback(
        schema: Schema,
        localConfiguration: ModelConfiguration,
        storeURL: URL,
        syncConflictService: SyncConflictService? = nil,
        preparePendingRecovery: (() -> Bool)? = nil,
        beforeDestructiveReset: (() -> Void)? = nil
    ) throws -> AppCloudSync.CloudRecoveryGate {
        try FileManager.default.createDirectory(
            at: storeURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let scope = TimerStoreScope(persistentStoreURL: storeURL)
        return try StoreScopedTimerMutationLock().withExclusiveAccess(for: scope) {
            try refreshLocalFallbackRecoverySnapshotBeforeCloudReset(
                schema: schema,
                localConfiguration: localConfiguration,
                syncConflictService: syncConflictService
            )
            let hasProtectedSnapshot = preparePendingRecovery?() ??
                AppCloudSync.preparePendingCloudRecoveryReset()
            beforeDestructiveReset?()
            return AppCloudSync.performPendingCloudRecoveryResetIfNeeded(
                canResetUpload: hasProtectedSnapshot,
                storeURL: storeURL
            )
        }
    }

    /// Local-fallback mutations commit to SwiftData before their independent
    /// recovery snapshot is updated. Reopen the still-intact local store and
    /// refresh that snapshot before a CloudKit recovery is allowed to delete
    /// the store on the next launch.
    static func refreshLocalFallbackRecoverySnapshotBeforeCloudReset(
        schema: Schema,
        localConfiguration: ModelConfiguration,
        syncConflictService: SyncConflictService? = nil
    ) throws {
        guard AppCloudSync.shouldRefreshLocalFallbackRecoverySnapshotBeforeReset else {
            return
        }

        // Keep the temporary container inside this called function so all of
        // its strong references are released before the caller removes the
        // SQLite files while retaining the outer store lock.
        try autoreleasepool {
            let localContainer = try ModelContainer(
                for: schema,
                migrationPlan: TimeTrackerMigrationPlan.self,
                configurations: [localConfiguration]
            )
            let context = ModelContext(localContainer)
            context.autosaveEnabled = false
            let resolvedService = syncConflictService ?? SyncConflictService()
            try resolvedService.refreshProtectedLocalFallbackSnapshotBeforeReset(
                context: context
            )
        }
    }

    static func makeEmergencyModelContainer(
        schema: Schema,
        configuration: ModelConfiguration,
        error: Error
    ) -> ModelContainer {
        AppCloudSync.recordEmergencyInMemoryFallback(error: error)
        do {
            return try ModelContainer(
                for: schema,
                migrationPlan: TimeTrackerMigrationPlan.self,
                configurations: [configuration]
            )
        } catch {
            preconditionFailure(
                "Could not create emergency in-memory ModelContainer: \(error)"
            )
        }
    }

    static func makeLocalFallbackModelContainer(
        schema: Schema,
        localConfiguration: ModelConfiguration,
        emergencyConfiguration: ModelConfiguration,
        error: Error
    ) -> ModelContainer {
        AppCloudSync.recordLocalFallback(error: error)
        do {
            return try ModelContainer(
                for: schema,
                migrationPlan: TimeTrackerMigrationPlan.self,
                configurations: [localConfiguration]
            )
        } catch {
            return makeEmergencyModelContainer(
                schema: schema,
                configuration: emergencyConfiguration,
                error: error
            )
        }
    }
}
