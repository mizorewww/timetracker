import Foundation
import SwiftData
import Testing
@testable import timetracker

@Suite(.serialized)
@MainActor
struct SyncConflictLocalMutationReplayTests {
    @Test
    func cloudReplayAcrossServicesDoesNotAdvanceGenerationOrRewriteState() throws {
        try withSyncMode(AppCloudSync.modeICloud) {
            let context = try makeTestContext()
            let task = TaskNode(
                title: "Shared base",
                parentID: nil,
                deviceID: "device-a"
            )
            context.insert(task)
            try context.save()

            let stateURL = temporaryStateURL()
            defer { removeTemporaryState(at: stateURL) }
            let firstService = SyncConflictService(stateURL: stateURL)
            #expect(try firstService.bootstrap(context: context) == nil)

            task.title = "Committed local edit"
            task.updatedAt = Date().addingTimeInterval(60)
            task.clientMutationID = UUID()
            try context.save()
            let event = StoreDomainEvent.taskChanged(
                taskID: task.id,
                affectedAncestorIDs: []
            )
            _ = try firstService.recordLocalMutation(
                context: context,
                events: [event]
            )

            let stateAfterFirstRecord = try firstService.loadState()
            let manifestAfterFirstRecord = try Data(contentsOf: stateURL)
            let writeProbe = DurableWriteProbe()
            let replayService = SyncConflictService(
                stateURL: stateURL,
                localStateFile: DurableLocalFile(injectFault: { point in
                    if point == .afterAtomicWriteBeforeFileSync {
                        writeProbe.recordWrite()
                    }
                })
            )

            let replayResult = try replayService.recordLocalMutation(
                context: context,
                events: [event]
            )
            guard case .recorded = replayResult else {
                Issue.record("Cloud-active replay must remain a successful recording")
                return
            }

            let stateAfterReplay = try replayService.loadState()
            #expect(
                stateAfterReplay.localGeneration ==
                    stateAfterFirstRecord.localGeneration
            )
            #expect(
                stateAfterReplay.localFingerprint ==
                    stateAfterFirstRecord.localFingerprint
            )
            #expect(try Data(contentsOf: stateURL) == manifestAfterFirstRecord)
            #expect(writeProbe.writeCount == 0)
        }
    }

    @Test
    func pendingConflictReplayDoesNotAdvanceGenerationOrRotateConflictIdentity() throws {
        try withSyncMode(AppCloudSync.modeICloud) {
            let context = try makeTestContext()
            let baseDate = Date()
            let task = TaskNode(
                title: "Protected local branch",
                parentID: nil,
                deviceID: "device-a"
            )
            task.updatedAt = baseDate.addingTimeInterval(120)
            context.insert(task)
            try context.save()

            let stateURL = temporaryStateURL()
            defer { removeTemporaryState(at: stateURL) }
            let firstService = SyncConflictService(stateURL: stateURL)
            #expect(try firstService.bootstrap(context: context) == nil)

            task.title = "Imported cloud branch"
            task.updatedAt = baseDate.addingTimeInterval(60)
            task.clientMutationID = UUID()
            try context.save()
            try insertUnmergeableSentinel(into: context)
            _ = try #require(
                try firstService.handleCloudImport(context: context)
            )

            let laterTask = TaskNode(
                title: "Post-conflict local edit",
                parentID: nil,
                deviceID: "device-a"
            )
            context.insert(laterTask)
            try context.save()
            let event = StoreDomainEvent.taskChanged(
                taskID: laterTask.id,
                affectedAncestorIDs: []
            )
            _ = try firstService.recordLocalMutation(
                context: context,
                events: [event]
            )

            let stateAfterFirstRecord = try firstService.loadState()
            let conflictIDAfterFirstRecord = try #require(
                stateAfterFirstRecord.pendingConflictID
            )
            let manifestAfterFirstRecord = try Data(contentsOf: stateURL)
            let writeProbe = DurableWriteProbe()
            let replayService = SyncConflictService(
                stateURL: stateURL,
                localStateFile: DurableLocalFile(injectFault: { point in
                    if point == .afterAtomicWriteBeforeFileSync {
                        writeProbe.recordWrite()
                    }
                })
            )

            let replayResult = try replayService.recordLocalMutation(
                context: context,
                events: [event]
            )
            guard case let .recorded(prompt) = replayResult else {
                Issue.record("Pending-conflict replay must remain a successful recording")
                return
            }

            let stateAfterReplay = try replayService.loadState()
            #expect(prompt?.id == conflictIDAfterFirstRecord)
            #expect(stateAfterReplay.pendingConflictID == conflictIDAfterFirstRecord)
            #expect(
                stateAfterReplay.localGeneration ==
                    stateAfterFirstRecord.localGeneration
            )
            #expect(try Data(contentsOf: stateURL) == manifestAfterFirstRecord)
            #expect(writeProbe.writeCount == 0)
        }
    }

    @Test
    func disabledSyncWithoutRecoveryDoesNotReadOrWriteConflictState() throws {
        try withSyncMode(AppCloudSync.modeLocal, enabled: false) {
            let context = try makeTestContext()
            context.insert(
                TaskNode(
                    title: "Device-only task",
                    parentID: nil,
                    deviceID: "device-a"
                )
            )
            try context.save()

            let stateURL = temporaryStateURL()
            defer { removeTemporaryState(at: stateURL) }
            let writeProbe = DurableWriteProbe()
            let service = SyncConflictService(
                stateURL: stateURL,
                localStateFile: DurableLocalFile(injectFault: { point in
                    if point == .afterAtomicWriteBeforeFileSync {
                        writeProbe.recordWrite()
                    }
                })
            )

            let result = try service.recordLocalMutation(context: context)
            guard case .notRecorded = result else {
                Issue.record("Disabled sync without recovery must not record a snapshot")
                return
            }

            #expect(FileManager.default.fileExists(atPath: stateURL.path) == false)
            #expect(writeProbe.writeCount == 0)
        }
    }

    private func insertUnmergeableSentinel(
        into context: ModelContext
    ) throws {
        context.insert(
            PomodoroRun(
                taskID: UUID(),
                focus: -120,
                breakSeconds: 60,
                longBreakSeconds: 300,
                targetRounds: 4,
                deviceID: "merge-sentinel"
            )
        )
        try context.save()
    }

    private func temporaryStateURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent(
                "SyncConflictLocalMutationReplay-\(UUID().uuidString)",
                isDirectory: true
            )
            .appendingPathComponent("state.json")
    }

    private func removeTemporaryState(at stateURL: URL) {
        try? FileManager.default.removeItem(
            at: stateURL.deletingLastPathComponent()
        )
    }

    private func withSyncMode(
        _ mode: String,
        enabled: Bool = true,
        _ operation: () throws -> Void
    ) throws {
        let defaults = AppDefaults.shared
        let keys = [
            AppCloudSync.modeKey,
            AppCloudSync.enabledKey,
            AppCloudSync.pendingCloudUploadResetKey,
            AppCloudSync.pendingCloudDownloadResetKey,
            AppCloudSync.queuedCloudReconciliationKey,
            AppCloudSync.activeCloudReconciliationKey,
            AppCloudSync.cloudRecoveryStoreResetKey,
            AppCloudSync.activeCloudDownloadRecoveryKey,
        ]
        let previousValues = keys.reduce(into: [String: Any]()) {
            values, key in
            if let value = defaults.object(forKey: key) {
                values[key] = value
            }
        }
        defer {
            for key in keys {
                if let value = previousValues[key] {
                    defaults.set(value, forKey: key)
                } else {
                    defaults.removeObject(forKey: key)
                }
            }
        }

        for key in keys {
            defaults.removeObject(forKey: key)
        }
        defaults.set(mode, forKey: AppCloudSync.modeKey)
        defaults.set(enabled, forKey: AppCloudSync.enabledKey)
        try operation()
    }
}

private final nonisolated class DurableWriteProbe: @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0

    var writeCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return count
    }

    func recordWrite() {
        lock.lock()
        count += 1
        lock.unlock()
    }
}
