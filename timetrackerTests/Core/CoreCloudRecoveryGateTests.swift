import Foundation
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
            source.range(of: "AppCloudSync.performPendingCloudRecoveryResetIfNeeded(")
        )
        let cloudContainer = try #require(
            source.range(of: "configurations: [cloudConfiguration]", options: .backwards)
        )

        #expect(demoBranch.lowerBound < disabledBranch.lowerBound)
        #expect(disabledBranch.lowerBound < recoveryGate.lowerBound)
        #expect(recoveryGate.lowerBound < cloudContainer.lowerBound)
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
        withRecoveryDefaults {
            let defaults = UserDefaults.standard
            defaults.set(true, forKey: AppCloudSync.pendingCloudUploadResetKey)
            var stateRemovalCount = 0

            let gate = AppCloudSync.performPendingCloudRecoveryResetIfNeeded(
                canResetUpload: true,
                storeURL: temporaryStoreURL(),
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
        withRecoveryDefaults {
            let defaults = UserDefaults.standard
            defaults.set(true, forKey: AppCloudSync.pendingCloudDownloadResetKey)
            var storeRemovalCount = 0

            let gate = AppCloudSync.performPendingCloudRecoveryResetIfNeeded(
                canResetUpload: false,
                storeURL: temporaryStoreURL(),
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
    func pendingMarkersClearOnlyAfterCompletedRecoveryIsAcknowledged() throws {
        withRecoveryDefaults {
            let defaults = UserDefaults.standard
            defaults.set(true, forKey: AppCloudSync.pendingCloudUploadResetKey)
            defaults.set("previous recovery error", forKey: AppCloudSync.errorKey)

            let gate = AppCloudSync.performPendingCloudRecoveryResetIfNeeded(
                canResetUpload: true,
                storeURL: temporaryStoreURL(),
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

    private enum ProbeError: Error {
        case unreadable
        case deletionFailed
    }
}
