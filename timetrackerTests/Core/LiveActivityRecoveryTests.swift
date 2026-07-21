import Foundation
import Testing
@testable import timetracker

@Suite(.serialized)
struct LiveActivityRecoveryTests {
    @Test
    func failuresExposeDistinctRecoveryActions() {
        #expect(LiveActivityFailure.denied.recovery == .openSettings)
        #expect(LiveActivityFailure.backgroundStart.recovery == .retryWhenForeground)
        #expect(LiveActivityFailure.capacity.recovery == .retry)
        #expect(LiveActivityFailure.removed.recovery == .retry)
        #expect(LiveActivityFailure.system.recovery == .retry)
        #expect(LiveActivityFailure.unsupported.recovery == .none)
        #expect(LiveActivityFailure.configuration.recovery == .none)
        #expect(LiveActivityFailure.payloadTooLarge.recovery == .none)
    }

    @Test @MainActor
    func latestDesiredStateCanBeRetriedAfterARequestFailure() async {
        let probe = ReconciliationAttemptProbe()
        let reconciler = LatestDesiredStateReconciler<String> { state in
            probe.record(state)
        }

        reconciler.submit("running")
        await reconciler.waitUntilIdle()
        #expect(probe.states == ["running"])

        reconciler.retryDesiredState()
        await reconciler.waitUntilIdle()
        #expect(probe.states == ["running", "running"])
        #expect(reconciler.desiredState == "running")
    }

    @Test @MainActor
    func retryRequestedDuringAnAttemptRunsAfterThatAttempt() async {
        let probe = BlockingReconciliationProbe()
        let reconciler = LatestDesiredStateReconciler<String> { state in
            await probe.reconcile(state)
        }

        reconciler.submit("running")
        while probe.attemptCount == 0 {
            await Task.yield()
        }

        reconciler.retryDesiredState()
        reconciler.retryDesiredState()
        probe.releaseFirstAttempt()
        await reconciler.waitUntilIdle()

        #expect(probe.states == ["running", "running"])
        #expect(reconciler.desiredState == "running")
    }

    @Test @MainActor
    func newerDesiredStateWinsOverAnInFlightRetry() async {
        let probe = BlockingReconciliationProbe()
        let reconciler = LatestDesiredStateReconciler<String> { state in
            await probe.reconcile(state)
        }

        reconciler.submit("running-a")
        while probe.attemptCount == 0 {
            await Task.yield()
        }

        reconciler.retryDesiredState()
        reconciler.submit("running-b")
        probe.releaseFirstAttempt()
        await reconciler.waitUntilIdle()

        #expect(probe.states == ["running-a", "running-b"])
        #expect(reconciler.desiredState == "running-b")
    }
}

@MainActor
private final class ReconciliationAttemptProbe {
    private(set) var states: [String] = []

    func record(_ state: String) {
        states.append(state)
    }
}

@MainActor
private final class BlockingReconciliationProbe {
    private(set) var states: [String] = []
    private var firstAttemptContinuation: CheckedContinuation<Void, Never>?

    var attemptCount: Int {
        states.count
    }

    func reconcile(_ state: String) async {
        states.append(state)
        guard states.count == 1 else { return }
        await withCheckedContinuation { continuation in
            firstAttemptContinuation = continuation
        }
    }

    func releaseFirstAttempt() {
        firstAttemptContinuation?.resume()
        firstAttemptContinuation = nil
    }
}
