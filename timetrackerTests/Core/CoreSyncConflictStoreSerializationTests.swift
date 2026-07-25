import Foundation
import SwiftData
import Testing
@testable import timetracker

@Suite(.serialized)
@MainActor
struct CoreSyncConflictStoreSerializationTests {
    @Test
    func storeTransactionCreatesAFreshContextInsideTheSharedLock() throws {
        let container = try timetrackerApp.makeUnitTestHostModelContainer()
        let originalContext = ModelContext(container)
        let service = SyncConflictService(stateURL: temporaryStateURL())
        let scope = try TimerStoreScope(container: container)
        let competitorEntered = DispatchSemaphore(value: 0)
        let competitorFinished = DispatchSemaphore(value: 0)
        let lock = StoreScopedTimerMutationLock()

        try service.withLockedFreshStoreContext(context: originalContext) { freshContext in
            #expect(freshContext !== originalContext)
            DispatchQueue.global().async {
                _ = try? lock.withExclusiveAccess(for: scope) {
                    competitorEntered.signal()
                }
                competitorFinished.signal()
            }
            #expect(competitorEntered.wait(timeout: .now() + 0.05) == .timedOut)
        }

        #expect(competitorEntered.wait(timeout: .now() + 2) == .success)
        #expect(competitorFinished.wait(timeout: .now() + 2) == .success)
    }

    @Test
    func snapshotEntrypointsAcquireStoreBeforeState() throws {
        let entrypoints = [
            (
                "func bootstrap(context: ModelContext)",
                "timetracker/Services/SystemIntegration/SyncConflictService.swift"
            ),
            (
                "func handleCloudImport(context: ModelContext)",
                "timetracker/Services/SystemIntegration/SyncConflictService+CloudImport.swift"
            ),
            (
                "func recordLocalMutation(context: ModelContext, events:",
                "timetracker/Services/SystemIntegration/SyncConflictService+LocalMutation.swift"
            ),
            (
                "func resolveSyncConflict(",
                "timetracker/Services/SystemIntegration/SyncConflictService+Resolution.swift"
            ),
            (
                "func stageCurrentLocalSnapshotForCloudEnablement(",
                "timetracker/Services/SystemIntegration/SyncConflictService+Recovery.swift"
            ),
            (
                "func forceUploadLocalData(context: ModelContext)",
                "timetracker/Services/SystemIntegration/SyncConflictService+Recovery.swift"
            ),
        ]

        for (signature, path) in entrypoints {
            let source = try sourceText(path)
            let function = try functionSource(signature: signature, in: source)
            let storeLock = try #require(
                function.range(of: "withLockedFreshStoreContext(context: context)")
            )
            let stateLock = try #require(function.range(of: "withExclusiveStateAccess"))
            #expect(storeLock.lowerBound < stateLock.lowerBound, "Lock order regressed in \(signature)")
        }

        let exportSource = try sourceText(
            "timetracker/Services/SystemIntegration/SyncConflictService+Export.swift"
        )
        let exportFunction = try functionSource(
            signature: "func exportCloudSyncedData(",
            in: exportSource
        )
        #expect(
            exportFunction.contains(
                "withLockedFreshStoreContext(context: context) { lockedContext in"
            )
        )
        #expect(exportFunction.contains("SyncDataSnapshot.capture(context: lockedContext)"))
    }

    private func functionSource(
        signature: String,
        in source: String
    ) throws -> Substring {
        let start = try #require(source.range(of: signature))
        let nextFunction = source.range(
            of: "\n    func ",
            range: start.upperBound ..< source.endIndex
        )
        let end = nextFunction?.lowerBound ?? source.endIndex
        return source[start.lowerBound ..< end]
    }

    private func temporaryStateURL() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent(
            "SyncConflictStoreSerialization-\(UUID().uuidString).json"
        )
    }
}
