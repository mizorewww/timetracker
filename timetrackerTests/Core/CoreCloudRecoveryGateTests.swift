import Foundation
import SwiftData
import Testing
@testable import timetracker

@Suite(.serialized)
struct CoreCloudRecoveryGateTests {
    @Test @MainActor
    func unreadableInitialConflictPromptBlocksEveryStartupWrite() throws {
        try withRecoveryDefaults {
            let defaults = AppDefaults.shared
            defaults.set(
                55,
                forKey: AppPreferenceKey.defaultFocusMinutes.rawValue
            )

            let fixtureRoot = FileManager.default.temporaryDirectory
                .appendingPathComponent(
                    "TimeTrackerStartupPromptGateTests-\(UUID().uuidString)",
                    isDirectory: true
                )
            defer { try? FileManager.default.removeItem(at: fixtureRoot) }
            let stateURL = fixtureRoot.appendingPathComponent("sync/state.json")
            try FileManager.default.createDirectory(
                at: stateURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try Data("{".utf8).write(to: stateURL)

            let context = try makeTestContext()
            let store = TimeTrackerStore(
                appleHealthDataReader: UnavailableAppleHealthDataReader(),
                appleHealthTimelinePreferenceStore:
                TestAppleHealthTimelinePreferenceStore(),
                writeAuthorization: .isolatedTestHarness,
                syncConflictService: SyncConflictService(stateURL: stateURL)
            )

            store.configureIfNeeded(context: context)

            #expect(store.hasCompletedStartupConfiguration == false)
            #expect(store.persistenceWriteSafety != .ready)
            #expect(store.errorMessage?.isEmpty == false)
            #expect(
                try context.fetch(FetchDescriptor<SyncedPreference>()).isEmpty
            )
            #expect(
                defaults.object(
                    forKey: AppPreferenceKey.defaultFocusMinutes.rawValue
                ) as? Int == 55
            )
            #expect(
                defaults.bool(forKey: SyncedPreferenceService.migrationKey) == false
            )
        }
    }

    @Test @MainActor
    func localFallbackPreflightRecapturesACommitMissedByPostCommitRecording() throws {
        try withRecoveryDefaults {
            let defaults = AppDefaults.shared
            defaults.set(true, forKey: AppCloudSync.enabledKey)
            defaults.set(AppCloudSync.modeLocalFallback, forKey: AppCloudSync.modeKey)

            let fixtureRoot = FileManager.default.temporaryDirectory
                .appendingPathComponent(
                    "TimeTrackerFallbackPreflightTests-\(UUID().uuidString)",
                    isDirectory: true
                )
            // The disk-backed container below may close SQLite sidecars
            // asynchronously. Leave this unique sandbox-temp fixture to the OS.
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

            guard case let .completed(recovery) = gate else {
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
    func missingAndUnreadableUploadBackupsDeferRecovery() {
        withRecoveryDefaults {
            let defaults = AppDefaults.shared
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

                guard case let .deferred(reason) = gate else {
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
    func noPendingRequestIsTheOnlyNoOpCompletion() {
        withRecoveryDefaults {
            var removalCount = 0
            let gate = AppCloudSync.performPendingCloudRecoveryResetIfNeeded(
                canResetUpload: false,
                storeURL: temporaryStoreURL(),
                removeStoreFiles: { _ in removalCount += 1 }
            )

            guard case let .completed(completion) = gate else {
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
            let defaults = AppDefaults.shared
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

            guard case let .failed(failure) = gate else {
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
            let defaults = AppDefaults.shared
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

            guard case let .failed(failure) = gate else {
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
            let defaults = AppDefaults.shared
            AppCloudSync.requestCloudDownloadReset()

            let gate = AppCloudSync.performPendingCloudRecoveryResetIfNeeded(
                canResetUpload: false,
                storeURL: temporaryStoreURL(),
                removeStoreFiles: { _ in },
                removeSyncConflictState: {},
                beginCloudImportSession: { _ in throw ProbeError.unreadable }
            )

            guard case let .failed(failure) = gate else {
                Issue.record("A missing durable import checkpoint must block recovery")
                return
            }
            #expect(failure.stage == .syncConflictStatePreparation)
            #expect(defaults.bool(forKey: AppCloudSync.pendingCloudDownloadResetKey))
            #expect(AppCloudSync.allowsUserWrites == false)
        }
    }

    @Test(
        arguments: [
            RecoveryLifecycleScenario(
                description: "explicit upload reset",
                canResetUpload: true,
                expectedReset: .upload,
                expectedImportKind: nil,
                request: {
                    let defaults = AppDefaults.shared
                    defaults.set(true, forKey: AppCloudSync.pendingCloudUploadResetKey)
                    defaults.set("previous recovery error", forKey: AppCloudSync.errorKey)
                },
                completeRecovery: { AppCloudSync.completeCloudReconciliation() },
                assertStateAfterPerform: {
                    let defaults = AppDefaults.shared
                    #expect(defaults.bool(forKey: AppCloudSync.pendingCloudUploadResetKey))
                    #expect(
                        defaults.string(forKey: AppCloudSync.errorKey)
                            == "previous recovery error"
                    )
                },
                assertStateAfterRecord: {
                    let defaults = AppDefaults.shared
                    #expect(
                        defaults.bool(forKey: AppCloudSync.pendingCloudUploadResetKey)
                            == false
                    )
                    #expect(
                        defaults.bool(forKey: AppCloudSync.pendingCloudDownloadResetKey)
                            == false
                    )
                    #expect(defaults.object(forKey: AppCloudSync.errorKey) == nil)
                    #expect(AppCloudSync.persistenceMode == AppCloudSync.modeICloud)
                    #expect(defaults.bool(forKey: AppCloudSync.cloudRecoveryStoreResetKey))
                }
            ),
            RecoveryLifecycleScenario(
                description: "queued reconciliation",
                canResetUpload: true,
                expectedReset: nil,
                expectedImportKind: .reconcileWithCloud,
                request: {
                    AppCloudSync.requestCloudReconciliationReset()
                    let defaults = AppDefaults.shared
                    #expect(defaults.bool(forKey: AppCloudSync.queuedCloudReconciliationKey))
                    #expect(AppCloudSync.isCloudReconciliationActive == false)
                    #expect(AppCloudSync.allowsUserWrites)
                },
                completeRecovery: { AppCloudSync.completeCloudReconciliation() },
                assertStateAfterPerform: {
                    #expect(
                        AppDefaults.shared.bool(
                            forKey: AppCloudSync.cloudRecoveryStoreResetKey
                        )
                    )
                },
                assertStateAfterRecord: {
                    let defaults = AppDefaults.shared
                    #expect(
                        defaults.bool(forKey: AppCloudSync.queuedCloudReconciliationKey)
                            == false
                    )
                    #expect(
                        defaults.bool(forKey: AppCloudSync.cloudRecoveryStoreResetKey)
                            == false
                    )
                    #expect(AppCloudSync.isCloudReconciliationActive)
                    #expect(
                        defaults.bool(forKey: AppCloudSync.pendingCloudUploadResetKey)
                            == false
                    )
                }
            ),
            RecoveryLifecycleScenario(
                description: "download reset",
                canResetUpload: false,
                expectedReset: nil,
                expectedImportKind: .downloadCloud,
                request: {
                    AppCloudSync.requestCloudDownloadReset()
                },
                completeRecovery: { AppCloudSync.completeCloudDownloadRecovery() },
                assertStateAfterPerform: {
                    #expect(
                        AppDefaults.shared.bool(
                            forKey: AppCloudSync.cloudRecoveryStoreResetKey
                        ) == false
                    )
                },
                assertStateAfterRecord: {
                    let defaults = AppDefaults.shared
                    #expect(
                        defaults.bool(forKey: AppCloudSync.pendingCloudDownloadResetKey)
                            == false
                    )
                    #expect(AppCloudSync.isCloudDownloadRecoveryActive)
                }
            ),
        ]
    )
    @MainActor
    private func successfulRecoveryStaysReadOnlyUntilItsBootstrapCompletes(
        scenario: RecoveryLifecycleScenario
    ) {
        withRecoveryDefaults {
            scenario.request()
            var startedImportKind: CloudRecoveryImportKind?
            let gate = AppCloudSync.performPendingCloudRecoveryResetIfNeeded(
                canResetUpload: scenario.canResetUpload,
                storeURL: temporaryStoreURL(),
                removeStoreFiles: { _ in },
                removeSyncConflictState: {},
                beginCloudImportSession: { startedImportKind = $0 }
            )

            guard case let .completed(completion) = gate else {
                Issue.record("\(scenario.description) reset should complete")
                return
            }
            if let expectedReset = scenario.expectedReset {
                #expect(completion.reset == expectedReset)
            }
            #expect(startedImportKind == scenario.expectedImportKind)
            scenario.assertStateAfterPerform()

            AppCloudSync.recordCloudKitEnabled(after: completion)
            scenario.assertStateAfterRecord()
            #expect(AppCloudSync.allowsUserWrites == false)

            scenario.completeRecovery()
            #expect(AppCloudSync.allowsUserWrites)
        }
    }

    @Test(arguments: FailedDestructiveResetRequest.allCases)
    @MainActor
    private func failedDestructiveResetKeepsFallbackReadOnly(
        requestKind: FailedDestructiveResetRequest
    ) {
        withRecoveryDefaults {
            requestKind.request()
            let gate = AppCloudSync.performPendingCloudRecoveryResetIfNeeded(
                canResetUpload: true,
                storeURL: temporaryStoreURL(),
                removeStoreFiles: { _ in throw ProbeError.deletionFailed }
            )

            guard case .failed = gate else {
                Issue.record("Failed destructive reset should remain pending")
                return
            }
            #expect(
                AppDefaults.shared.bool(
                    forKey: AppCloudSync.cloudRecoveryStoreResetKey
                )
            )
            #expect(AppCloudSync.allowsUserWrites == false)
        }
    }

    @Test @MainActor
    func persistedIntentReconstructsMissingRecoveryDefaultsBeforeContainerCreation() {
        withRecoveryDefaults {
            #expect(AppCloudSync.preparePendingCloudRecoveryReset(
                hasProtectedSnapshot: { true },
                loadIntent: { .reconcileWithCloud }
            ))
            #expect(AppDefaults.shared.bool(forKey: AppCloudSync.pendingCloudUploadResetKey))
            #expect(AppDefaults.shared.bool(forKey: AppCloudSync.queuedCloudReconciliationKey))

            AppCloudSync.completeCloudReconciliation()
            AppDefaults.shared.removeObject(forKey: AppCloudSync.pendingCloudUploadResetKey)
            #expect(AppCloudSync.preparePendingCloudRecoveryReset(
                hasProtectedSnapshot: { true },
                loadIntent: { .explicitlyReplaceCloud }
            ))
            #expect(AppDefaults.shared.bool(forKey: AppCloudSync.pendingCloudUploadResetKey))
            #expect(AppDefaults.shared.bool(forKey: AppCloudSync.queuedCloudReconciliationKey) == false)
        }
    }

    @Test @MainActor
    func interruptedImportRecoveryReusesOnlyAJournaledFreshStore() {
        withRecoveryDefaults {
            let defaults = AppDefaults.shared

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
            let defaults = AppDefaults.shared

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
            let defaults = AppDefaults.shared
            defaults.set(true, forKey: AppCloudSync.pendingCloudUploadResetKey)
            defaults.set(true, forKey: AppCloudSync.pendingCloudDownloadResetKey)
            var removalCount = 0

            let gate = AppCloudSync.performPendingCloudRecoveryResetIfNeeded(
                canResetUpload: true,
                storeURL: temporaryStoreURL(),
                removeStoreFiles: { _ in removalCount += 1 }
            )

            guard case let .deferred(reason) = gate else {
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
            let defaults = AppDefaults.shared
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
            let defaults = AppDefaults.shared
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

            guard case let .completed(completion) = gate else {
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
    func realStoreCleanupRemovesStoreFilesAndPreservesMutationLock() throws {
        try withRecoveryDefaults {
            let storeURL = try makeTemporaryStoreURL()
            defer { removeTemporaryStoreDirectory(for: storeURL) }
            let defaults = AppDefaults.shared
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

            guard case let .completed(completion) = gate else {
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
        let defaults = AppDefaults.shared
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
            SeedData.automaticDemoSeedingDisabledKey,
            SyncedPreferenceService.migrationKey,
            AppPreferenceKey.defaultFocusMinutes.rawValue,
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

    private enum FailedDestructiveResetRequest: String, CaseIterable, CustomStringConvertible {
        case reconciliation
        case explicitUpload

        var description: String {
            rawValue
        }

        @MainActor
        func request() {
            switch self {
            case .reconciliation:
                AppCloudSync.requestCloudReconciliationReset()
            case .explicitUpload:
                AppCloudSync.requestCloudUploadReset()
            }
        }
    }

    private struct RecoveryLifecycleScenario: Sendable, CustomStringConvertible {
        let description: String
        let canResetUpload: Bool
        let expectedReset: AppCloudSync.CloudRecoveryReset?
        let expectedImportKind: CloudRecoveryImportKind?
        let request: @MainActor () -> Void
        let completeRecovery: @MainActor () -> Void
        let assertStateAfterPerform: @MainActor () -> Void
        let assertStateAfterRecord: @MainActor () -> Void
    }
}
