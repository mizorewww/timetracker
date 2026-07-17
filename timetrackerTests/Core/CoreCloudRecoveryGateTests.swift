import Foundation
import SwiftData
import Testing
@testable import timetracker

@Suite(.serialized)
struct CoreCloudRecoveryGateTests {
    @Test
    func factoryRunsRecoveryOnlyInsideTheEnabledCloudBranch() throws {
        let source = try sourceText("timetracker/App/AppModelContainerFactory.swift")
        let demoBranch = try #require(source.range(of: "if AppDemoDataConfiguration.usesLocalDemoStore"))
        let disabledBranch = try #require(source.range(of: "guard AppCloudSync.isEnabled else"))
        let recoveryGate = try #require(
            source.range(of: "performPendingCloudRecoveryResetAfterProtectingLocalFallback(")
        )
        let cloudContainer = try #require(
            source.range(of: "configurations: [cloudConfiguration]", options: .backwards)
        )

        #expect(demoBranch.lowerBound < disabledBranch.lowerBound)
        #expect(disabledBranch.lowerBound < recoveryGate.lowerBound)
        #expect(recoveryGate.lowerBound < cloudContainer.lowerBound)
    }

    @Test
    func factoryKeepsFallbackProtectionAndDestructiveRecoveryUnderOneStoreLock() throws {
        let factorySource = try sourceText("timetracker/App/AppModelContainerFactory.swift")
        let fallbackSource = try sourceText(
            "timetracker/App/AppModelContainerFactory+Fallback.swift"
        )
        #expect(
            factorySource.contains(
                "performPendingCloudRecoveryResetAfterProtectingLocalFallback("
            )
        )
        let outerLock = try #require(
            fallbackSource.range(of: "StoreScopedTimerMutationLock().withExclusiveAccess")
        )
        let fallbackRefresh = try #require(
            fallbackSource.range(
                of: "refreshLocalFallbackRecoverySnapshotBeforeCloudReset(",
                range: outerLock.lowerBound..<fallbackSource.endIndex
            )
        )
        let recoveryPreparation = try #require(
            fallbackSource.range(
                of: "AppCloudSync.preparePendingCloudRecoveryReset()",
                range: fallbackRefresh.lowerBound..<fallbackSource.endIndex
            )
        )
        let destructiveRecovery = try #require(
            fallbackSource.range(
                of: "AppCloudSync.performPendingCloudRecoveryResetIfNeeded(",
                range: recoveryPreparation.lowerBound..<fallbackSource.endIndex
            )
        )

        #expect(outerLock.lowerBound < fallbackRefresh.lowerBound)
        #expect(fallbackRefresh.lowerBound < recoveryPreparation.lowerBound)
        #expect(recoveryPreparation.lowerBound < destructiveRecovery.lowerBound)
    }

    @Test @MainActor
    func localFallbackPreflightRecapturesACommitMissedByPostCommitRecording() throws {
        try withRecoveryDefaults {
            let defaults = UserDefaults.standard
            defaults.set(true, forKey: AppCloudSync.enabledKey)
            defaults.set(AppCloudSync.modeLocalFallback, forKey: AppCloudSync.modeKey)

            let fixtureRoot = FileManager.default.temporaryDirectory
                .appendingPathComponent(
                    "TimeTrackerFallbackPreflightTests-\(UUID().uuidString)",
                    isDirectory: true
                )
            defer { try? FileManager.default.removeItem(at: fixtureRoot) }
            let storeURL = fixtureRoot.appendingPathComponent("fallback.store")
            let stateURL = fixtureRoot.appendingPathComponent("sync/state.json")
            let schema = TimeTrackerModelRegistry.currentSchema
            let configuration = ModelConfiguration(
                "FallbackCrashWindow",
                schema: schema,
                url: storeURL,
                cloudKitDatabase: .none
            )
            let service = SyncConflictService(stateURL: stateURL)

            try autoreleasepool {
                let container = try ModelContainer(
                    for: schema,
                    migrationPlan: TimeTrackerMigrationPlan.self,
                    configurations: [configuration]
                )
                let context = ModelContext(container)
                context.autosaveEnabled = false
                let task = TaskNode(
                    title: "Protected before commit",
                    parentID: nil,
                    deviceID: "local"
                )
                context.insert(task)
                try context.save()
                #expect(try service.forceUploadLocalData(context: context) == .queuedForNextLaunch)

                // Simulate termination after this commit but before the normal
                // post-commit recorder can refresh the independent snapshot.
                task.title = "Latest committed fallback edit"
                task.updatedAt = Date().addingTimeInterval(60)
                task.clientMutationID = UUID()
                try context.save()
            }

            #expect(
                try service.loadPendingForcedUploadSnapshot()?.tasks.map(\.title) ==
                    ["Protected before commit"]
            )

            let competingWriterEntered = DispatchSemaphore(value: 0)
            let competingWriterFinished = DispatchSemaphore(value: 0)
            let scope = TimerStoreScope(persistentStoreURL: storeURL)
            let gate = try timetrackerApp.performPendingCloudRecoveryResetAfterProtectingLocalFallback(
                schema: schema,
                localConfiguration: configuration,
                storeURL: storeURL,
                syncConflictService: service,
                preparePendingRecovery: { true },
                beforeDestructiveReset: {
                    DispatchQueue.global().async {
                        _ = try? StoreScopedTimerMutationLock().withExclusiveAccess(for: scope) {
                            competingWriterEntered.signal()
                        }
                        competingWriterFinished.signal()
                    }
                    #expect(
                        competingWriterEntered.wait(timeout: .now() + 0.05) == .timedOut
                    )
                }
            )

            guard case .completed(let recovery) = gate else {
                Issue.record("Protected fallback recovery should complete")
                return
            }
            #expect(recovery.reset == .upload)
            #expect(
                try service.loadPendingForcedUploadSnapshot()?.tasks.map(\.title) ==
                    ["Latest committed fallback edit"]
            )
            #expect(FileManager.default.fileExists(atPath: storeURL.path) == false)
            #expect(competingWriterEntered.wait(timeout: .now() + 1) == .success)
            #expect(competingWriterFinished.wait(timeout: .now() + 1) == .success)
        }
    }

    @Test @MainActor
    func explicitDownloadRecoveryDoesNotRecaptureTheLocalFallbackBranch() {
        withRecoveryDefaults {
            let defaults = UserDefaults.standard
            defaults.set(true, forKey: AppCloudSync.enabledKey)
            defaults.set(AppCloudSync.modeLocalFallback, forKey: AppCloudSync.modeKey)
            defaults.set(true, forKey: AppCloudSync.pendingCloudDownloadResetKey)

            #expect(AppCloudSync.shouldRefreshLocalFallbackRecoverySnapshotBeforeReset == false)
        }
    }

    @Test @MainActor
    func missingAndUnreadableUploadBackupsDeferRecovery() throws {
        withRecoveryDefaults {
            let defaults = UserDefaults.standard
            let missingBackup = SyncConflictService.hasDefaultPendingForcedUploadBackup(
                loadAuthoritativeSnapshot: { nil },
                loadRecoveryMirror: { nil }
            )
            let unreadableBackup = SyncConflictService.hasDefaultPendingForcedUploadBackup(
                loadAuthoritativeSnapshot: { throw ProbeError.unreadable },
                loadRecoveryMirror: { throw ProbeError.unreadable }
            )

            #expect(missingBackup == false)
            #expect(unreadableBackup == false)

            for canResetUpload in [missingBackup, unreadableBackup] {
                defaults.set(true, forKey: AppCloudSync.pendingCloudUploadResetKey)
                var removalCount = 0
                let gate = AppCloudSync.performPendingCloudRecoveryResetIfNeeded(
                    canResetUpload: canResetUpload,
                    storeURL: temporaryStoreURL(),
                    removeStoreFiles: { _ in removalCount += 1 }
                )

                guard case .deferred(let reason) = gate else {
                    Issue.record("Unavailable upload backup must defer CloudKit recovery")
                    continue
                }
                #expect(reason == .protectedUploadSnapshotUnavailable)
                #expect(removalCount == 0)
                #expect(defaults.bool(forKey: AppCloudSync.pendingCloudUploadResetKey))
            }
        }
    }

    @Test @MainActor
    func noPendingRequestIsTheOnlyNoOpCompletion() throws {
        withRecoveryDefaults {
            var removalCount = 0
            let gate = AppCloudSync.performPendingCloudRecoveryResetIfNeeded(
                canResetUpload: false,
                storeURL: temporaryStoreURL(),
                removeStoreFiles: { _ in removalCount += 1 }
            )

            guard case .completed(let completion) = gate else {
                Issue.record("No pending recovery should complete without work")
                return
            }
            #expect(completion.reset == .none)
            #expect(removalCount == 0)
        }
    }

    @Test @MainActor
    func persistentStoreDeletionFailureKeepsUploadPending() throws {
        try withRecoveryDefaults {
            let defaults = UserDefaults.standard
            defaults.set(true, forKey: AppCloudSync.pendingCloudUploadResetKey)
            var stateRemovalCount = 0
            let storeURL = try makeTemporaryStoreURL()
            defer { removeTemporaryStoreDirectory(for: storeURL) }

            let gate = AppCloudSync.performPendingCloudRecoveryResetIfNeeded(
                canResetUpload: true,
                storeURL: storeURL,
                removeStoreFiles: { _ in throw ProbeError.deletionFailed },
                removeSyncConflictState: { stateRemovalCount += 1 }
            )

            guard case .failed(let failure) = gate else {
                Issue.record("Store deletion failure must block CloudKit recovery")
                return
            }
            #expect(failure.stage == .persistentStoreRemoval)
            #expect(stateRemovalCount == 0)
            #expect(defaults.bool(forKey: AppCloudSync.pendingCloudUploadResetKey))
        }
    }

    @Test @MainActor
    func downloadStateDeletionFailureKeepsDownloadPending() throws {
        try withRecoveryDefaults {
            let defaults = UserDefaults.standard
            defaults.set(true, forKey: AppCloudSync.pendingCloudDownloadResetKey)
            var storeRemovalCount = 0
            let storeURL = try makeTemporaryStoreURL()
            defer { removeTemporaryStoreDirectory(for: storeURL) }

            let gate = AppCloudSync.performPendingCloudRecoveryResetIfNeeded(
                canResetUpload: false,
                storeURL: storeURL,
                removeStoreFiles: { _ in storeRemovalCount += 1 },
                removeSyncConflictState: { throw ProbeError.deletionFailed }
            )

            guard case .failed(let failure) = gate else {
                Issue.record("State deletion failure must block CloudKit recovery")
                return
            }
            #expect(failure.stage == .syncConflictStateRemoval)
            #expect(storeRemovalCount == 1)
            #expect(defaults.bool(forKey: AppCloudSync.pendingCloudDownloadResetKey))
        }
    }

    @Test @MainActor
    func importSessionWriteFailureKeepsRecoveryPendingAndReadOnly() {
        withRecoveryDefaults {
            let defaults = UserDefaults.standard
            AppCloudSync.requestCloudDownloadReset()

            let gate = AppCloudSync.performPendingCloudRecoveryResetIfNeeded(
                canResetUpload: false,
                storeURL: temporaryStoreURL(),
                removeStoreFiles: { _ in },
                removeSyncConflictState: {},
                beginCloudImportSession: { _ in throw ProbeError.unreadable }
            )

            guard case .failed(let failure) = gate else {
                Issue.record("A missing durable import checkpoint must block recovery")
                return
            }
            #expect(failure.stage == .syncConflictStatePreparation)
            #expect(defaults.bool(forKey: AppCloudSync.pendingCloudDownloadResetKey))
            #expect(AppCloudSync.allowsUserWrites == false)
        }
    }

    @Test @MainActor
    func explicitUploadResetStaysReadOnlyUntilBootstrapRestoresProtectedData() throws {
        try withRecoveryDefaults {
            let defaults = UserDefaults.standard
            defaults.set(true, forKey: AppCloudSync.pendingCloudUploadResetKey)
            defaults.set("previous recovery error", forKey: AppCloudSync.errorKey)
            let storeURL = try makeTemporaryStoreURL()
            defer { removeTemporaryStoreDirectory(for: storeURL) }

            let gate = AppCloudSync.performPendingCloudRecoveryResetIfNeeded(
                canResetUpload: true,
                storeURL: storeURL,
                removeStoreFiles: { _ in }
            )

            guard case .completed(let completion) = gate else {
                Issue.record("Successful reset must produce a completion token")
                return
            }
            #expect(completion.reset == .upload)
            #expect(defaults.bool(forKey: AppCloudSync.pendingCloudUploadResetKey))
            #expect(defaults.string(forKey: AppCloudSync.errorKey) == "previous recovery error")

            AppCloudSync.recordCloudKitEnabled(after: completion)

            #expect(defaults.bool(forKey: AppCloudSync.pendingCloudUploadResetKey) == false)
            #expect(defaults.bool(forKey: AppCloudSync.pendingCloudDownloadResetKey) == false)
            #expect(defaults.object(forKey: AppCloudSync.errorKey) == nil)
            #expect(AppCloudSync.persistenceMode == AppCloudSync.modeICloud)
            #expect(defaults.bool(forKey: AppCloudSync.cloudRecoveryStoreResetKey))
            #expect(AppCloudSync.allowsUserWrites == false)

            AppCloudSync.completeCloudReconciliation()
            #expect(AppCloudSync.allowsUserWrites)
        }
    }

    @Test @MainActor
    func queuedReconciliationBecomesActiveOnlyAfterCloudContainerStarts() throws {
        withRecoveryDefaults {
            let defaults = UserDefaults.standard
            AppCloudSync.requestCloudReconciliationReset()
            #expect(defaults.bool(forKey: AppCloudSync.queuedCloudReconciliationKey))
            #expect(AppCloudSync.isCloudReconciliationActive == false)
            #expect(AppCloudSync.allowsUserWrites)
            var startedImportKind: CloudRecoveryImportKind?

            let gate = AppCloudSync.performPendingCloudRecoveryResetIfNeeded(
                canResetUpload: true,
                storeURL: temporaryStoreURL(),
                removeStoreFiles: { _ in },
                beginCloudImportSession: { startedImportKind = $0 }
            )
            guard case .completed(let completion) = gate else {
                Issue.record("Reconciliation reset should complete")
                return
            }
            #expect(startedImportKind == .reconcileWithCloud)
            #expect(defaults.bool(forKey: AppCloudSync.cloudRecoveryStoreResetKey))
            #expect(AppCloudSync.allowsUserWrites == false)

            AppCloudSync.recordCloudKitEnabled(after: completion)
            #expect(defaults.bool(forKey: AppCloudSync.queuedCloudReconciliationKey) == false)
            #expect(defaults.bool(forKey: AppCloudSync.cloudRecoveryStoreResetKey) == false)
            #expect(AppCloudSync.isCloudReconciliationActive)
            #expect(defaults.bool(forKey: AppCloudSync.pendingCloudUploadResetKey) == false)
            #expect(AppCloudSync.allowsUserWrites == false)

            AppCloudSync.completeCloudReconciliation()
            #expect(AppCloudSync.allowsUserWrites)
        }
    }

    @Test @MainActor
    func failedDestructiveReconciliationResetKeepsFallbackReadOnly() throws {
        withRecoveryDefaults {
            AppCloudSync.requestCloudReconciliationReset()
            let gate = AppCloudSync.performPendingCloudRecoveryResetIfNeeded(
                canResetUpload: true,
                storeURL: temporaryStoreURL(),
                removeStoreFiles: { _ in throw ProbeError.deletionFailed }
            )

            guard case .failed = gate else {
                Issue.record("Failed destructive reset should remain pending")
                return
            }
            #expect(UserDefaults.standard.bool(forKey: AppCloudSync.cloudRecoveryStoreResetKey))
            #expect(AppCloudSync.allowsUserWrites == false)
        }
    }

    @Test @MainActor
    func failedExplicitUploadResetAlsoKeepsFallbackReadOnly() {
        withRecoveryDefaults {
            AppCloudSync.requestCloudUploadReset()
            let gate = AppCloudSync.performPendingCloudRecoveryResetIfNeeded(
                canResetUpload: true,
                storeURL: temporaryStoreURL(),
                removeStoreFiles: { _ in throw ProbeError.deletionFailed }
            )

            guard case .failed = gate else {
                Issue.record("Failed explicit reset should remain pending")
                return
            }
            #expect(UserDefaults.standard.bool(forKey: AppCloudSync.cloudRecoveryStoreResetKey))
            #expect(AppCloudSync.allowsUserWrites == false)
        }
    }

    @Test @MainActor
    func downloadResetKeepsRecoveryReadOnlyUntilServiceCompletesIt() {
        withRecoveryDefaults {
            let defaults = UserDefaults.standard
            AppCloudSync.requestCloudDownloadReset()
            var startedImportKind: CloudRecoveryImportKind?
            let gate = AppCloudSync.performPendingCloudRecoveryResetIfNeeded(
                canResetUpload: false,
                storeURL: temporaryStoreURL(),
                removeStoreFiles: { _ in },
                removeSyncConflictState: {},
                beginCloudImportSession: { startedImportKind = $0 }
            )
            guard case .completed(let completion) = gate else {
                Issue.record("Download reset should complete")
                return
            }
            #expect(startedImportKind == .downloadCloud)
            #expect(defaults.bool(forKey: AppCloudSync.cloudRecoveryStoreResetKey) == false)

            AppCloudSync.recordCloudKitEnabled(after: completion)
            #expect(defaults.bool(forKey: AppCloudSync.pendingCloudDownloadResetKey) == false)
            #expect(AppCloudSync.isCloudDownloadRecoveryActive)
            #expect(AppCloudSync.allowsUserWrites == false)

            AppCloudSync.completeCloudDownloadRecovery()
            #expect(AppCloudSync.allowsUserWrites)
        }
    }

    @Test @MainActor
    func persistedIntentReconstructsMissingRecoveryDefaultsBeforeContainerCreation() {
        withRecoveryDefaults {
            #expect(AppCloudSync.preparePendingCloudRecoveryReset(
                hasProtectedSnapshot: { true },
                loadIntent: { .reconcileWithCloud }
            ))
            #expect(UserDefaults.standard.bool(forKey: AppCloudSync.pendingCloudUploadResetKey))
            #expect(UserDefaults.standard.bool(forKey: AppCloudSync.queuedCloudReconciliationKey))

            AppCloudSync.completeCloudReconciliation()
            UserDefaults.standard.removeObject(forKey: AppCloudSync.pendingCloudUploadResetKey)
            #expect(AppCloudSync.preparePendingCloudRecoveryReset(
                hasProtectedSnapshot: { true },
                loadIntent: { .explicitlyReplaceCloud }
            ))
            #expect(UserDefaults.standard.bool(forKey: AppCloudSync.pendingCloudUploadResetKey))
            #expect(UserDefaults.standard.bool(forKey: AppCloudSync.queuedCloudReconciliationKey) == false)
        }
    }

    @Test @MainActor
    func interruptedImportRecoveryReusesOnlyAJournaledFreshStore() {
        withRecoveryDefaults {
            let defaults = UserDefaults.standard

            defaults.set(true, forKey: AppCloudSync.activeCloudDownloadRecoveryKey)
            AppCloudSync.prepareInterruptedCloudDownloadRecovery(
                hasCompletedImportSession: { true }
            )
            #expect(defaults.bool(forKey: AppCloudSync.pendingCloudDownloadResetKey) == false)

            AppCloudSync.prepareInterruptedCloudDownloadRecovery(
                hasCompletedImportSession: { false }
            )
            #expect(defaults.bool(forKey: AppCloudSync.pendingCloudDownloadResetKey))

            defaults.removeObject(forKey: AppCloudSync.pendingCloudDownloadResetKey)
            defaults.removeObject(forKey: AppCloudSync.activeCloudDownloadRecoveryKey)
            defaults.set(true, forKey: AppCloudSync.activeCloudReconciliationKey)
            #expect(AppCloudSync.preparePendingCloudRecoveryReset(
                hasProtectedSnapshot: { true },
                loadIntent: { .reconcileWithCloud },
                hasCompletedImportSession: { true }
            ))
            #expect(defaults.bool(forKey: AppCloudSync.pendingCloudUploadResetKey) == false)
            #expect(defaults.bool(forKey: AppCloudSync.queuedCloudReconciliationKey) == false)
        }
    }

    @Test @MainActor
    func recoveryRequestsAreMutuallyExclusiveAndLastChoiceWins() {
        withRecoveryDefaults {
            let defaults = UserDefaults.standard

            defaults.set(true, forKey: AppCloudSync.activeCloudReconciliationKey)
            defaults.set(true, forKey: AppCloudSync.activeCloudDownloadRecoveryKey)
            AppCloudSync.requestCloudDownloadReset()
            #expect(defaults.bool(forKey: AppCloudSync.pendingCloudDownloadResetKey))
            #expect(defaults.bool(forKey: AppCloudSync.pendingCloudUploadResetKey) == false)
            #expect(defaults.bool(forKey: AppCloudSync.activeCloudReconciliationKey) == false)
            #expect(defaults.bool(forKey: AppCloudSync.activeCloudDownloadRecoveryKey) == false)

            AppCloudSync.requestCloudReconciliationReset()
            #expect(defaults.bool(forKey: AppCloudSync.pendingCloudUploadResetKey))
            #expect(defaults.bool(forKey: AppCloudSync.queuedCloudReconciliationKey))
            #expect(defaults.bool(forKey: AppCloudSync.pendingCloudDownloadResetKey) == false)

            AppCloudSync.requestCloudUploadReset()
            #expect(defaults.bool(forKey: AppCloudSync.pendingCloudUploadResetKey))
            #expect(defaults.bool(forKey: AppCloudSync.pendingCloudDownloadResetKey) == false)
            #expect(defaults.bool(forKey: AppCloudSync.queuedCloudReconciliationKey) == false)
        }
    }

    @Test @MainActor
    func conflictingLegacyRecoveryRequestsCannotDeleteTheStore() {
        withRecoveryDefaults {
            let defaults = UserDefaults.standard
            defaults.set(true, forKey: AppCloudSync.pendingCloudUploadResetKey)
            defaults.set(true, forKey: AppCloudSync.pendingCloudDownloadResetKey)
            var removalCount = 0

            let gate = AppCloudSync.performPendingCloudRecoveryResetIfNeeded(
                canResetUpload: true,
                storeURL: temporaryStoreURL(),
                removeStoreFiles: { _ in removalCount += 1 }
            )

            guard case .deferred(let reason) = gate else {
                Issue.record("Conflicting legacy recovery requests must require a new choice")
                return
            }
            #expect(reason == .conflictingRecoveryRequests)
            #expect(removalCount == 0)
            #expect(AppCloudSync.allowsUserWrites == false)
        }
    }

    @Test @MainActor
    func cancellingReconciliationDoesNotCancelAnUnrelatedExplicitUpload() {
        withRecoveryDefaults {
            let defaults = UserDefaults.standard
            defaults.set(true, forKey: AppCloudSync.pendingCloudUploadResetKey)
            AppCloudSync.cancelCloudReconciliation()
            #expect(defaults.bool(forKey: AppCloudSync.pendingCloudUploadResetKey))

            AppCloudSync.requestCloudReconciliationReset()
            AppCloudSync.cancelCloudReconciliation()
            #expect(defaults.bool(forKey: AppCloudSync.pendingCloudUploadResetKey) == false)
            #expect(defaults.bool(forKey: AppCloudSync.queuedCloudReconciliationKey) == false)
            #expect(defaults.bool(forKey: AppCloudSync.activeCloudReconciliationKey) == false)
            #expect(defaults.bool(forKey: AppCloudSync.cloudRecoveryStoreResetKey) == false)

            defaults.set(true, forKey: AppCloudSync.activeCloudDownloadRecoveryKey)
            AppCloudSync.recordUITesting()
            #expect(defaults.bool(forKey: AppCloudSync.activeCloudDownloadRecoveryKey) == false)
        }
    }

    @Test @MainActor
    func recoveryDeletionKeepsTheStoreLockAndRunsStateCleanupInsideIt() throws {
        try withRecoveryDefaults {
            let storeURL = try makeTemporaryStoreURL()
            defer { removeTemporaryStoreDirectory(for: storeURL) }
            let defaults = UserDefaults.standard
            defaults.set(true, forKey: AppCloudSync.pendingCloudDownloadResetKey)
            let scope = TimerStoreScope(persistentStoreURL: storeURL)
            let lock = StoreScopedTimerMutationLock()
            let competitorEntered = DispatchSemaphore(value: 0)
            let competitorFinished = DispatchSemaphore(value: 0)
            var competitorWasBlockedDuringStoreRemoval = false
            var competitorWasBlockedDuringStateRemoval = false

            let gate = AppCloudSync.performPendingCloudRecoveryResetIfNeeded(
                canResetUpload: false,
                storeURL: storeURL,
                removeStoreFiles: { _ in
                    DispatchQueue.global().async {
                        _ = try? lock.withExclusiveAccess(for: scope) {
                            competitorEntered.signal()
                        }
                        competitorFinished.signal()
                    }
                    competitorWasBlockedDuringStoreRemoval =
                        competitorEntered.wait(timeout: .now() + 0.05) == .timedOut
                },
                removeSyncConflictState: {
                    competitorWasBlockedDuringStateRemoval =
                        competitorEntered.wait(timeout: .now() + 0.05) == .timedOut
                },
                beginCloudImportSession: { _ in }
            )

            guard case .completed(let completion) = gate else {
                Issue.record("Locked download recovery should complete")
                return
            }
            #expect(completion.reset == .download)
            #expect(competitorWasBlockedDuringStoreRemoval)
            #expect(competitorWasBlockedDuringStateRemoval)
            #expect(competitorEntered.wait(timeout: .now() + 2) == .success)
            #expect(competitorFinished.wait(timeout: .now() + 2) == .success)
        }
    }

    @Test @MainActor
    func realStoreCleanupDeletesSQLiteFilesButPreservesTheMutationLock() throws {
        try withRecoveryDefaults {
            let storeURL = try makeTemporaryStoreURL()
            defer { removeTemporaryStoreDirectory(for: storeURL) }
            let defaults = UserDefaults.standard
            defaults.set(true, forKey: AppCloudSync.pendingCloudUploadResetKey)
            let suffixes = ["", "-wal", "-shm"]
            for suffix in suffixes {
                #expect(
                    FileManager.default.createFile(
                        atPath: storeURL.path + suffix,
                        contents: Data("fixture".utf8)
                    )
                )
            }
            let lockURL = TimerStoreScope(
                persistentStoreURL: storeURL
            ).mutationLockURL
            #expect(
                FileManager.default.createFile(
                    atPath: lockURL.path,
                    contents: Data()
                )
            )

            let gate = AppCloudSync.performPendingCloudRecoveryResetIfNeeded(
                canResetUpload: true,
                storeURL: storeURL
            )

            guard case .completed(let completion) = gate else {
                Issue.record("Real locked store cleanup should complete")
                return
            }
            #expect(completion.reset == .upload)
            for suffix in suffixes {
                #expect(FileManager.default.fileExists(atPath: storeURL.path + suffix) == false)
            }
            #expect(FileManager.default.fileExists(atPath: lockURL.path))
        }
    }

    @MainActor
    private func withRecoveryDefaults(_ operation: () throws -> Void) rethrows {
        let defaults = UserDefaults.standard
        let keys = [
            AppCloudSync.enabledKey,
            AppCloudSync.modeKey,
            AppCloudSync.errorKey,
            AppCloudSync.pendingCloudUploadResetKey,
            AppCloudSync.pendingCloudDownloadResetKey,
            AppCloudSync.queuedCloudReconciliationKey,
            AppCloudSync.activeCloudReconciliationKey,
            AppCloudSync.cloudRecoveryStoreResetKey,
            AppCloudSync.activeCloudDownloadRecoveryKey,
            AppDemoDataConfiguration.overrideKey,
            SeedData.automaticDemoSeedingDisabledKey
        ]
        let previousValues = Dictionary(uniqueKeysWithValues: keys.map { ($0, defaults.object(forKey: $0)) })
        keys.forEach { defaults.removeObject(forKey: $0) }
        defer {
            for key in keys {
                if let previousValue = previousValues[key] {
                    defaults.set(previousValue, forKey: key)
                } else {
                    defaults.removeObject(forKey: key)
                }
            }
        }
        try operation()
    }

    private func temporaryStoreURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("TimeTrackerCloudRecoveryGateTests-\(UUID().uuidString)")
            .appendingPathComponent("TimeTracker.store")
    }

    private func makeTemporaryStoreURL() throws -> URL {
        let storeURL = temporaryStoreURL()
        try FileManager.default.createDirectory(
            at: storeURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        return storeURL
    }

    private func removeTemporaryStoreDirectory(for storeURL: URL) {
        try? FileManager.default.removeItem(
            at: storeURL.deletingLastPathComponent()
        )
    }

    private enum ProbeError: Error {
        case unreadable
        case deletionFailed
    }
}
