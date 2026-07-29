import Foundation
import Testing
@testable import timetracker

@Suite(.serialized)
struct CoreSyncActivityOutcomeTests {
    @Test @MainActor
    func earlyCloudImportBufferIsIdempotentAndReleasesItsObserver() {
        let buffer = CloudRecoveryImportBuffer(
            center: NotificationCenter(),
            recordReceipt: { _ in }
        )
        let reason = TimeTrackerStore.SyncRefreshReason.cloudImportFinished(
            succeeded: true,
            reportsConflict: false,
            failureMessage: nil
        )

        buffer.startIfNeeded()
        buffer.startIfNeeded()
        #expect(buffer.isObserving)
        buffer.record(reason)
        #expect(buffer.stopAndDrain().count == 1)
        #expect(buffer.isObserving == false)
        #expect(buffer.stopAndDrain().isEmpty)

        buffer.startIfNeeded()
        buffer.record(reason)
        buffer.stopAndDiscard()
        #expect(buffer.isObserving == false)
        #expect(buffer.stopAndDrain().isEmpty)
    }

    @Test
    func initialCloudImportReceiptRequiresCurrentEpochSetupAndMatchingStore() {
        let epoch = Date(timeIntervalSinceReferenceDate: 50000)
        var session = CloudRecoveryImportSession(
            id: UUID(),
            kind: .downloadCloud,
            startedAt: epoch
        )

        session.record(receipt(
            store: "store-a",
            kind: .import,
            startedAt: epoch.addingTimeInterval(2)
        ))
        #expect(session.hasCompletedInitialImport == false)

        session.record(receipt(
            store: "store-a",
            kind: .setup,
            startedAt: epoch.addingTimeInterval(-1)
        ))
        session.record(receipt(
            store: "store-a",
            kind: .setup,
            startedAt: epoch.addingTimeInterval(1),
            succeeded: false
        ))
        #expect(session.storeIdentifier == nil)

        session.record(receipt(
            store: "store-a",
            kind: .setup,
            startedAt: epoch.addingTimeInterval(1)
        ))
        session.record(receipt(
            store: "store-a",
            kind: .import,
            startedAt: epoch.addingTimeInterval(1.25)
        ))
        #expect(session.hasCompletedInitialImport == false)
        session.record(receipt(
            store: "store-b",
            kind: .import,
            startedAt: epoch.addingTimeInterval(2)
        ))
        #expect(session.hasCompletedInitialImport == false)

        session.record(receipt(
            store: "store-a",
            kind: .import,
            startedAt: epoch.addingTimeInterval(3)
        ))
        #expect(session.hasCompletedInitialImport)
    }

    @Test @MainActor
    func cloudRecoveryReceiptsPersistAcrossServiceRecreation() throws {
        let stateURL = temporaryStateURL()
        defer { try? FileManager.default.removeItem(at: stateURL.deletingLastPathComponent()) }
        let epoch = Date(timeIntervalSinceReferenceDate: 60000)
        let firstService = SyncConflictService(stateURL: stateURL)
        try firstService.beginCloudRecoveryImportSession(
            kind: .downloadCloud,
            startedAt: epoch
        )
        let firstSessionID = try #require(
            try firstService.loadState().cloudRecoveryImportSession?.id
        )
        try firstService.recordCloudRecoveryContainerEvent(receipt(
            store: "persisted-store",
            kind: .setup,
            startedAt: epoch.addingTimeInterval(1)
        ))

        let secondService = SyncConflictService(stateURL: stateURL)
        try secondService.recordCloudRecoveryContainerEvent(receipt(
            store: "persisted-store",
            kind: .import,
            startedAt: epoch.addingTimeInterval(2)
        ))

        let thirdService = SyncConflictService(stateURL: stateURL)
        let completed = try #require(
            try thirdService.loadState().cloudRecoveryImportSession
        )
        #expect(completed.id == firstSessionID)
        #expect(completed.kind == .downloadCloud)
        #expect(completed.storeIdentifier == "persisted-store")
        #expect(completed.setupCompletedAt != nil)
        #expect(completed.initialImportCompletedAt != nil)
        #expect(completed.hasCompletedInitialImport)

        try thirdService.beginCloudRecoveryImportSession(
            kind: .reconcileWithCloud,
            startedAt: epoch.addingTimeInterval(10)
        )
        let replacement = try #require(
            try thirdService.loadState().cloudRecoveryImportSession
        )
        #expect(replacement.id != firstSessionID)
        #expect(replacement.kind == .reconcileWithCloud)
        #expect(replacement.storeIdentifier == nil)
        #expect(replacement.setupCompletedAt == nil)
        #expect(replacement.initialImportCompletedAt == nil)
    }

    @Test @MainActor
    func failedCloudEventCannotBecomeRecentGreenActivity() throws {
        let completedAt = Date(timeIntervalSinceReferenceDate: 10000)
        let reason = TimeTrackerStore.SyncRefreshReason.cloudExportFinished(
            eventID: UUID(),
            succeeded: false,
            reportsConflict: false,
            failureMessage: "Network unavailable"
        )
        let outcome = try #require(reason.activityOutcome(completedAt: completedAt))

        #expect(outcome == SyncActivityOutcome(
            kind: .exportData,
            completedAt: completedAt,
            result: .failed(message: "Network unavailable")
        ))

        var preferences = AppPreferences.defaults
        preferences.cloudSyncEnabled = true
        let feedback = cloudStatus().feedback(
            preferences: preferences,
            isChecking: false,
            activity: outcome,
            now: completedAt.addingTimeInterval(10)
        )
        #expect(feedback.state == .failed)
        #expect(feedback.message == "Network unavailable")
    }

    @Test @MainActor
    func onlySuccessfulCompletedCloudEventBecomesRecentActivity() throws {
        let completedAt = Date(timeIntervalSinceReferenceDate: 20000)
        let reason = TimeTrackerStore.SyncRefreshReason.cloudImportFinished(
            succeeded: true,
            reportsConflict: false,
            failureMessage: nil
        )
        let outcome = try #require(reason.activityOutcome(completedAt: completedAt))

        #expect(outcome.kind == .importData)
        #expect(outcome.result == .succeeded)

        var preferences = AppPreferences.defaults
        preferences.cloudSyncEnabled = true
        let feedback = cloudStatus().feedback(
            preferences: preferences,
            isChecking: false,
            activity: outcome,
            now: completedAt.addingTimeInterval(10)
        )
        #expect(feedback.state == .recentlySynced)
    }

    @Test @MainActor
    func localProcessingFailureOverridesSuccessfulCloudEvent() throws {
        let completedAt = Date(timeIntervalSinceReferenceDate: 30000)
        let reason = TimeTrackerStore.SyncRefreshReason.cloudImportFinished(
            succeeded: true,
            reportsConflict: false,
            failureMessage: nil
        )
        let outcome = try #require(reason.activityOutcome(
            completedAt: completedAt,
            processingFailureMessage: "Could not refresh local data"
        ))

        #expect(outcome.result == .failed(message: "Could not refresh local data"))
    }

    @Test @MainActor
    func remoteStoreSignalAloneDoesNotClaimCloudCompletion() {
        let reason = TimeTrackerStore.SyncRefreshReason.remoteStoreChanged

        #expect(reason.activityOutcome(completedAt: Date()) == nil)
    }

    @Test @MainActor
    func futureCompletionTimestampDoesNotBecomeRecentActivity() {
        let now = Date(timeIntervalSinceReferenceDate: 40000)
        let outcome = SyncActivityOutcome(
            kind: .setup,
            completedAt: now.addingTimeInterval(30),
            result: .succeeded
        )
        var preferences = AppPreferences.defaults
        preferences.cloudSyncEnabled = true

        let feedback = cloudStatus().feedback(
            preferences: preferences,
            isChecking: false,
            activity: outcome,
            now: now
        )

        #expect(feedback.state == .available)
    }

    @Test @MainActor
    func coalescingPreservesImportHandlingWhileSelectingTheHighestSeverityActivity() {
        let success = TimeTrackerStore.SyncRefreshReason.cloudImportFinished(
            succeeded: true,
            reportsConflict: false,
            failureMessage: nil
        )
        let failure = TimeTrackerStore.SyncRefreshReason.cloudExportFinished(
            eventID: UUID(),
            succeeded: false,
            reportsConflict: false,
            failureMessage: "Failed"
        )
        let conflict = TimeTrackerStore.SyncRefreshReason.cloudImportFinished(
            succeeded: false,
            reportsConflict: true,
            failureMessage: "Conflict"
        )

        var batch = TimeTrackerStore.SyncRefreshBatch()
        batch.insert(success)
        batch.insert(failure)

        #expect(batch.requiresCloudImportHandling)
        #expect(batch.hasSuccessfulCloudImport)
        #expect(batch.activityReason?.priority == failure.priority)

        batch.insert(conflict)
        #expect(batch.requiresCloudImportHandling)
        #expect(batch.hasSuccessfulCloudImport == false)
        #expect(batch.activityReason?.priority == conflict.priority)

        var failedImportOnly = TimeTrackerStore.SyncRefreshBatch()
        failedImportOnly.insert(conflict)
        #expect(failedImportOnly.requiresCloudImportHandling)
        #expect(failedImportOnly.hasSuccessfulCloudImport == false)

        var exportOnly = TimeTrackerStore.SyncRefreshBatch()
        exportOnly.insert(failure)
        #expect(exportOnly.requiresReadModelCatchUp == false)

        exportOnly.insert(.remoteStoreChanged)
        #expect(exportOnly.requiresReadModelCatchUp)
    }

    @Test @MainActor
    func coalescingStateStaysBoundedUnderAContinuousNotificationBurst() throws {
        var batch = TimeTrackerStore.SyncRefreshBatch()
        for _ in 0 ..< 10000 {
            batch.insert(.remoteStoreChanged)
        }
        batch.insert(
            .cloudImportFinished(
                succeeded: true,
                reportsConflict: false,
                failureMessage: nil
            )
        )

        #expect(batch.activityReason?.activityKind == .importData)
        #expect(batch.requiresCloudImportHandling)
        #expect(batch.hasSuccessfulCloudImport)

        let source = try sourceText(
            "timetracker/Stores/Facade/TimeTrackerStore+SyncRefreshPipeline.swift"
        )
        #expect(source.contains("guard scheduledSyncRefreshTask == nil else { return }"))
        #expect(source.contains("scheduledSyncRefreshTask?.cancel()") == false)
    }

    private func cloudStatus() -> SyncStatus {
        SyncStatus(
            mode: AppCloudSync.modeICloud,
            containerIdentifier: "iCloud.test",
            deviceID: "test",
            lastError: nil,
            accountCheck: CloudAccountCheckOutcome(
                checkedAt: Date(),
                result: .available
            )
        )
    }

    private func receipt(
        store: String,
        kind: CloudRecoveryContainerEventReceipt.EventKind,
        startedAt: Date,
        succeeded: Bool = true
    ) -> CloudRecoveryContainerEventReceipt {
        CloudRecoveryContainerEventReceipt(
            storeIdentifier: store,
            kind: kind,
            startedAt: startedAt,
            completedAt: startedAt.addingTimeInterval(0.5),
            succeeded: succeeded
        )
    }

    private func temporaryStateURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("CloudRecoveryReceiptTests-\(UUID().uuidString)", isDirectory: true)
            .appendingPathComponent("SyncState.json")
    }
}
