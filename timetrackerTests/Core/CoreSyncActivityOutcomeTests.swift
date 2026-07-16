import Foundation
import Testing
@testable import timetracker

@Suite(.serialized)
struct CoreSyncActivityOutcomeTests {
    @Test @MainActor
    func failedCloudEventCannotBecomeRecentGreenActivity() throws {
        let completedAt = Date(timeIntervalSinceReferenceDate: 10_000)
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
        let completedAt = Date(timeIntervalSinceReferenceDate: 20_000)
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
        let completedAt = Date(timeIntervalSinceReferenceDate: 30_000)
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
        let now = Date(timeIntervalSinceReferenceDate: 40_000)
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
    func failureAndConflictReasonsOutrankSuccessfulEventsDuringCoalescing() {
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

        #expect(failure.priority > success.priority)
        #expect(conflict.priority > failure.priority)
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
}
