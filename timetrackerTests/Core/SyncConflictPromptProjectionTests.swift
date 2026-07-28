import Foundation
import Testing
@testable import timetracker

@Suite(.serialized)
struct SyncConflictPromptProjectionTests {
    @Test @MainActor
    func projectionSignalLoadsTheCurrentPromptWithoutBlockingMainActor()
        async
    {
        let prompt = makePrompt(summary: "Projected")
        let gate = SyncPromptLoadGate()
        let store = makePromptStore {
            try await gate.load()
        }
        store.installSyncObservers()
        defer {
            store.removeStoreMutationObserver()
        }

        SyncConflictPromptChangeBroadcaster.publish()
        await gate.waitUntilStarted()

        var heartbeat = false
        await Task.yield()
        heartbeat = true
        #expect(heartbeat)
        #expect(store.pendingSyncConflict == nil)

        await gate.release(with: .success(prompt))
        await store.waitForSyncConflictPromptRefresh()
        #expect(store.pendingSyncConflict == prompt)
    }

    @Test @MainActor
    func newerPromptStateDiscardsAnOlderSuspendedLoad() async {
        let stalePrompt = makePrompt(summary: "Stale")
        let currentPrompt = makePrompt(summary: "Current")
        let gate = SyncPromptLoadGate()
        let store = makePromptStore {
            try await gate.load()
        }

        store.scheduleSyncConflictPromptRefresh()
        await gate.waitUntilStarted()
        store.replacePendingSyncConflict(currentPrompt)
        await gate.release(with: .success(stalePrompt))
        await store.waitForSyncConflictPromptRefresh()

        #expect(store.pendingSyncConflict == currentPrompt)
    }

    @Test @MainActor
    func promptLoadFailurePreservesTheLastKnownPresentationState() async {
        let currentPrompt = makePrompt(summary: "Retained")
        let store = makePromptStore {
            throw SyncPromptLoadFailure.expected
        }
        store.replacePendingSyncConflict(currentPrompt)

        store.scheduleSyncConflictPromptRefresh()
        await store.waitForSyncConflictPromptRefresh()

        #expect(store.pendingSyncConflict == currentPrompt)
        #expect(store.errorMessage == nil)
    }

    @Test @MainActor
    func transientPromptLoadFailureRetriesWithoutAnotherNotification()
        async
    {
        let prompt = makePrompt(summary: "Recovered")
        let loader = SyncPromptSequenceLoader(
            results: [
                .failure(SyncPromptLoadFailure.expected),
                .success(prompt),
            ]
        )
        let store = makePromptStore {
            try await loader.load()
        }

        store.scheduleSyncConflictPromptRefresh()
        await store.waitForSyncConflictPromptRefresh()

        #expect(store.pendingSyncConflict == prompt)
        #expect(await loader.callCount == 2)
    }

    @Test @MainActor
    func notificationBurstKeepsOneLoadInFlightAndOneTrailingRefresh()
        async
    {
        let stalePrompt = makePrompt(summary: "Stale")
        let currentPrompt = makePrompt(summary: "Current")
        let gate = SyncPromptBurstGate(
            first: stalePrompt,
            trailing: currentPrompt
        )
        let store = makePromptStore {
            await gate.load()
        }

        store.scheduleSyncConflictPromptRefresh()
        await gate.waitUntilFirstStarted()
        for _ in 0 ..< 20 {
            store.scheduleSyncConflictPromptRefresh()
        }
        await Task.yield()
        await gate.releaseFirst()
        await store.waitForSyncConflictPromptRefresh()

        #expect(store.pendingSyncConflict == currentPrompt)
        #expect(await gate.callCount == 2)
        #expect(await gate.maximumConcurrentLoadCount == 1)
    }

    @MainActor
    private func makePromptStore(
        loader: @escaping TimeTrackerStore.SyncConflictPromptLoader
    ) -> TimeTrackerStore {
        TimeTrackerStore(
            appleHealthDataReader: UnavailableAppleHealthDataReader(),
            appleHealthTimelinePreferenceStore:
            TestAppleHealthTimelinePreferenceStore(),
            writeAuthorization: .isolatedTestHarness,
            syncConflictPromptLoader: loader
        )
    }

    private func makePrompt(summary: String) -> SyncConflictPrompt {
        SyncConflictPrompt(
            id: UUID(),
            detectedAt: Date(timeIntervalSinceReferenceDate: 100),
            localSummary: summary,
            cloudSummary: "Cloud"
        )
    }
}

private enum SyncPromptLoadFailure: Error {
    case expected
}

private actor SyncPromptSequenceLoader {
    private var results: [
        Result<SyncConflictPrompt?, any Error>
    ]
    private(set) var callCount = 0

    init(
        results: [Result<SyncConflictPrompt?, any Error>]
    ) {
        self.results = results
    }

    func load() throws -> SyncConflictPrompt? {
        callCount += 1
        guard results.isEmpty == false else {
            throw SyncPromptLoadFailure.expected
        }
        return try results.removeFirst().get()
    }
}

private actor SyncPromptBurstGate {
    private let first: SyncConflictPrompt?
    private let trailing: SyncConflictPrompt?
    private var firstStarted = false
    private var firstStartWaiters: [
        CheckedContinuation<Void, Never>
    ] = []
    private var firstReleaseWaiters: [
        CheckedContinuation<Void, Never>
    ] = []
    private var activeLoadCount = 0
    private(set) var callCount = 0
    private(set) var maximumConcurrentLoadCount = 0

    init(
        first: SyncConflictPrompt?,
        trailing: SyncConflictPrompt?
    ) {
        self.first = first
        self.trailing = trailing
    }

    func load() async -> SyncConflictPrompt? {
        callCount += 1
        let call = callCount
        activeLoadCount += 1
        maximumConcurrentLoadCount = max(
            maximumConcurrentLoadCount,
            activeLoadCount
        )
        defer {
            activeLoadCount -= 1
        }

        guard call == 1 else {
            return trailing
        }
        firstStarted = true
        let waiters = firstStartWaiters
        firstStartWaiters.removeAll()
        for waiter in waiters {
            waiter.resume()
        }
        await withCheckedContinuation { continuation in
            firstReleaseWaiters.append(continuation)
        }
        return first
    }

    func waitUntilFirstStarted() async {
        guard firstStarted == false else { return }
        await withCheckedContinuation { continuation in
            firstStartWaiters.append(continuation)
        }
    }

    func releaseFirst() {
        let waiters = firstReleaseWaiters
        firstReleaseWaiters.removeAll()
        for waiter in waiters {
            waiter.resume()
        }
    }
}

private actor SyncPromptLoadGate {
    private var didStart = false
    private var startWaiters: [CheckedContinuation<Void, Never>] = []
    private var result:
        Result<SyncConflictPrompt?, any Error>?
    private var resultWaiters: [
        CheckedContinuation<
            Result<SyncConflictPrompt?, any Error>,
            Never
        >
    ] = []

    func load() async throws -> SyncConflictPrompt? {
        didStart = true
        let waiters = startWaiters
        startWaiters.removeAll()
        for waiter in waiters {
            waiter.resume()
        }
        let result = if let result {
            result
        } else {
            await withCheckedContinuation { continuation in
                resultWaiters.append(continuation)
            }
        }
        return try result.get()
    }

    func waitUntilStarted() async {
        guard didStart == false else { return }
        await withCheckedContinuation { continuation in
            startWaiters.append(continuation)
        }
    }

    func release(
        with result: Result<SyncConflictPrompt?, any Error>
    ) {
        self.result = result
        let waiters = resultWaiters
        resultWaiters.removeAll()
        for waiter in waiters {
            waiter.resume(returning: result)
        }
    }
}
