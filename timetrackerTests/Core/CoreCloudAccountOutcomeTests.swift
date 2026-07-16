import CloudKit
import Foundation
import Testing
@testable import timetracker

@Suite(.serialized)
struct CoreCloudAccountOutcomeTests {
    @Test @MainActor
    func accountCheckerMapsEveryKnownCloudKitStatus() async {
        let checkedAt = Date(timeIntervalSinceReferenceDate: 123)
        let expectations: [(CKAccountStatus, CloudAccountCheckResult)] = [
            (.available, .available),
            (.noAccount, .unavailable(.noAccount)),
            (.restricted, .unavailable(.restricted)),
            (.couldNotDetermine, .unavailable(.couldNotDetermine)),
            (.temporarilyUnavailable, .unavailable(.temporarilyUnavailable))
        ]

        for (status, expectedResult) in expectations {
            let outcome = await AppCloudSync.checkAccountStatus(
                client: CloudAccountStatusClient { status },
                checkedAt: checkedAt
            )
            #expect(outcome == CloudAccountCheckOutcome(
                checkedAt: checkedAt,
                result: expectedResult
            ))
        }
    }

    @Test @MainActor
    func accountCheckerPreservesThrownFailureWithoutPersistingDisplayText() async {
        let defaults = UserDefaults.standard
        let previousValue = defaults.object(forKey: AppCloudSync.accountStatusKey)
        defaults.set("legacy localized status", forKey: AppCloudSync.accountStatusKey)
        defer {
            if let previousValue {
                defaults.set(previousValue, forKey: AppCloudSync.accountStatusKey)
            } else {
                defaults.removeObject(forKey: AppCloudSync.accountStatusKey)
            }
        }

        let outcome = await AppCloudSync.checkAccountStatus(
            client: CloudAccountStatusClient { throw ProbeError.networkUnavailable },
            checkedAt: Date(timeIntervalSinceReferenceDate: 456)
        )

        guard case let .failed(message) = outcome.result else {
            Issue.record("Thrown account checks must remain typed failures")
            return
        }
        #expect(message.isEmpty == false)
        #expect(defaults.string(forKey: AppCloudSync.accountStatusKey) == "legacy localized status")
    }

    @Test @MainActor
    func accountUnavailableOverridesARecentSuccessfulCloudActivity() {
        var preferences = AppPreferences.defaults
        preferences.cloudSyncEnabled = true
        let now = Date(timeIntervalSinceReferenceDate: 789)
        let status = SyncStatus(
            mode: AppCloudSync.modeICloud,
            containerIdentifier: "iCloud.test",
            deviceID: "test",
            lastError: nil,
            accountCheck: CloudAccountCheckOutcome(
                checkedAt: now,
                result: .unavailable(.noAccount)
            )
        )

        let feedback = status.feedback(
            preferences: preferences,
            isChecking: false,
            activity: SyncActivityOutcome(
                kind: .importData,
                completedAt: now.addingTimeInterval(-30),
                result: .succeeded
            ),
            now: now
        )

        #expect(feedback.state == .offline)
        #expect(feedback.title == AppStrings.localized("sync.state.accountUnavailable.title"))
        #expect(feedback.message == AppStrings.localized("sync.account.noAccount"))
    }

    @Test @MainActor
    func newestStartedAccountCheckOwnsStoreState() async {
        let store = makeTestStore()
        let probe = AccountStatusContinuationProbe()
        let firstDate = Date(timeIntervalSinceReferenceDate: 1_000)
        let secondDate = firstDate.addingTimeInterval(1)

        let first = Task { @MainActor in
            await store.refreshCloudAccountStatus(
                client: CloudAccountStatusClient { await probe.fetch("first") },
                checkedAt: firstDate
            )
        }
        await probe.waitUntilRequested("first")

        let second = Task { @MainActor in
            await store.refreshCloudAccountStatus(
                client: CloudAccountStatusClient { await probe.fetch("second") },
                checkedAt: secondDate
            )
        }
        await probe.waitUntilRequested("second")
        await probe.resume("second", with: .available)
        _ = await second.value
        await probe.resume("first", with: .noAccount)
        _ = await first.value

        #expect(store.cloudAccountCheck == CloudAccountCheckOutcome(
            checkedAt: secondDate,
            result: .available
        ))
        #expect(store.lastSyncActivity == nil)
    }

    private enum ProbeError: LocalizedError {
        case networkUnavailable

        var errorDescription: String? { "Network unavailable" }
    }
}

private actor AccountStatusContinuationProbe {
    private var continuations: [String: CheckedContinuation<CKAccountStatus, Never>] = [:]

    func fetch(_ key: String) async -> CKAccountStatus {
        await withCheckedContinuation { continuation in
            continuations[key] = continuation
        }
    }

    func waitUntilRequested(_ key: String) async {
        while continuations[key] == nil {
            await Task.yield()
        }
    }

    func resume(_ key: String, with status: CKAccountStatus) {
        continuations.removeValue(forKey: key)?.resume(returning: status)
    }
}
