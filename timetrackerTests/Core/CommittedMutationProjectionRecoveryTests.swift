import CloudKit
import Foundation
import SwiftData
import Testing
@testable import timetracker

@Suite(.serialized)
struct CommittedMutationProjectionRecoveryTests {
    @Test @MainActor
    func startupSchedulesDurableProjectionCatchUpWithoutWaitingForEffects()
        async throws
    {
        let recorder = ProjectionRecoveryRecorder()
        let scheduler = CommittedMutationSystemProjectionScheduler {
            sink,
            work in
            recorder.record(sink: sink, work: work)
        }
        let store = makeRecoveryStore(scheduler: scheduler)
        let context = try makeTestContext()

        store.configureIfNeeded(context: context)

        #expect(store.hasCompletedStartupConfiguration)
        await scheduler.waitUntilIdle()
        #expect(recorder.callsBySink.count == 4)
        for sink in CommittedMutationSystemProjectionSink.allCases {
            let work = try #require(recorder.callsBySink[sink]?.first)
            #expect(work.events == [.fullSync])
            #expect(
                work.forceCurrentStateProjection
                    == (sink == .watch)
            )
        }
    }

    @Test @MainActor
    func foregroundSchedulesAnotherCatchUpAfterStartup() async throws {
        let recorder = ProjectionRecoveryRecorder()
        let scheduler = CommittedMutationSystemProjectionScheduler {
            sink,
            work in
            recorder.record(sink: sink, work: work)
        }
        let store = makeRecoveryStore(scheduler: scheduler)
        try store.configureIfNeeded(context: makeTestContext())
        await scheduler.waitUntilIdle()

        await store.refreshForForeground(
            cloudAccountStatusClient: CloudAccountStatusClient {
                .available
            }
        )
        await scheduler.waitUntilIdle()

        for sink in CommittedMutationSystemProjectionSink.allCases {
            #expect(recorder.callsBySink[sink]?.count == 2)
            #expect(recorder.callsBySink[sink]?.last?.events == [.fullSync])
        }
    }

    @Test @MainActor
    func foregroundAlsoReloadsDurableConflictPresentation() async throws {
        let prompt = SyncConflictPrompt(
            id: UUID(),
            detectedAt: Date(timeIntervalSinceReferenceDate: 100),
            localSummary: "Local",
            cloudSummary: "Cloud"
        )
        let scheduler =
            CommittedMutationSystemProjectionScheduler { _, _ in }
        let store = makeRecoveryStore(
            scheduler: scheduler,
            syncConflictPromptLoader: {
                prompt
            }
        )
        try store.configureIfNeeded(context: makeTestContext())

        await store.refreshForForeground(
            cloudAccountStatusClient: CloudAccountStatusClient {
                .available
            }
        )
        await store.waitForSyncConflictPromptRefresh()

        #expect(store.pendingSyncConflict == prompt)
    }

    @Test @MainActor
    func remoteImportSchedulesCatchUpWithoutRepeatingSceneSideEffects()
        async throws
    {
        let recorder = ProjectionRecoveryRecorder()
        let scheduler = CommittedMutationSystemProjectionScheduler {
            sink,
            work in
            recorder.record(sink: sink, work: work)
        }
        let store = makeRecoveryStore(scheduler: scheduler)
        try store.configureIfNeeded(context: makeTestContext())
        await scheduler.waitUntilIdle()

        store.scheduleQuietRefresh(reason: .remoteStoreChanged)
        try await Task.sleep(for: .milliseconds(500))
        await scheduler.waitUntilIdle()

        for sink in CommittedMutationSystemProjectionSink.allCases {
            #expect(recorder.callsBySink[sink]?.count == 2)
            #expect(
                recorder.callsBySink[sink]?.last?.events ==
                    [.remoteImportCompleted]
            )
        }
    }

    @Test @MainActor
    func completedCloudExportDoesNotRepeatReadModelProjection() async throws {
        let recorder = ProjectionRecoveryRecorder()
        let scheduler = CommittedMutationSystemProjectionScheduler {
            sink,
            work in
            recorder.record(sink: sink, work: work)
        }
        let store = makeRecoveryStore(scheduler: scheduler)
        try store.configureIfNeeded(context: makeTestContext())
        await scheduler.waitUntilIdle()

        store.scheduleQuietRefresh(reason: .cloudExportFinished(
            eventID: UUID(),
            succeeded: true,
            reportsConflict: false,
            failureMessage: nil
        ))
        try await Task.sleep(for: .milliseconds(500))
        await scheduler.waitUntilIdle()

        for sink in CommittedMutationSystemProjectionSink.allCases {
            #expect(recorder.callsBySink[sink]?.count == 1)
        }
    }

    @MainActor
    private func makeRecoveryStore(
        scheduler: CommittedMutationSystemProjectionScheduler,
        syncConflictPromptLoader:
        TimeTrackerStore.SyncConflictPromptLoader? = nil
    ) -> TimeTrackerStore {
        TimeTrackerStore(
            appleHealthDataReader: UnavailableAppleHealthDataReader(),
            appleHealthTimelinePreferenceStore:
            TestAppleHealthTimelinePreferenceStore(),
            writeAuthorization: .isolatedTestHarness,
            syncConflictPromptLoader: syncConflictPromptLoader,
            committedMutationSystemProjectionScheduler: scheduler
        )
    }
}

@MainActor
private final class ProjectionRecoveryRecorder {
    private(set) var callsBySink: [
        CommittedMutationSystemProjectionSink:
            [CommittedMutationSystemProjectionWork]
    ] = [:]

    func record(
        sink: CommittedMutationSystemProjectionSink,
        work: CommittedMutationSystemProjectionWork
    ) {
        callsBySink[sink, default: []].append(work)
    }
}
