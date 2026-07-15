import Foundation
import OSLog

#if canImport(WatchConnectivity)
import WatchConnectivity
#endif

extension WatchAppStore {
    func activate() {
        #if canImport(WatchConnectivity)
        guard WCSession.isSupported() else { return }
        let session = WCSession.default
        session.delegate = self
        session.activate()
        applyPayload(session.receivedApplicationContext)
        isReachable = session.isReachable
        for command in pendingCommands {
            scheduleConfirmationTimeout(for: command)
        }
        #endif
    }
}

#if canImport(WatchConnectivity)
extension WatchAppStore {
    /// Every attempt is put on the durable user-info channel. A reachable
    /// message is an acceleration path, not the only copy of the command.
    func transmit(_ command: WatchTimerCommand) {
        let payload = WatchConnectivityPayloadCodec.encode(command: command)
        let session = WCSession.default
        session.transferUserInfo(payload)
        isReachable = session.isReachable

        guard session.activationState == .activated, session.isReachable else { return }
        session.sendMessage(payload) { [weak self] reply in
            Task { @MainActor in
                guard let self else { return }
                self.isReachable = true
                self.hasConnectivityError = false
                self.applyPayload(reply)
            }
        } errorHandler: { [weak self] error in
            Task { @MainActor in
                self?.recordConnectivityError(error)
            }
        }
    }

    func applyPayload(_ payload: [String: Any]) {
        if let result = WatchConnectivityPayloadCodec.decodeCommandResult(from: payload) {
            applyCommandResult(result)
            return
        }
        if let state = WatchConnectivityPayloadCodec.decodeState(from: payload) {
            applyState(state)
        }
    }

    func applyCommandResult(_ result: WatchCommandResult) {
        guard commandQueue.resolve(result) != nil else { return }
        confirmationTasks[result.commandID]?.cancel()
        confirmationTasks[result.commandID] = nil
        hasConnectivityError = false
    }

    func applyState(_ state: WatchStateSnapshot) {
        snapshot = state
        hasReceivedSnapshot = true
        hasConnectivityError = false
        scheduleSnapshotFreshness(for: state)

        let confirmedCommandIDs = commandQueue.confirmReflectedCommands(in: state)
        for commandID in confirmedCommandIDs {
            confirmationTasks[commandID]?.cancel()
            confirmationTasks[commandID] = nil
        }
    }

    func scheduleSnapshotFreshness(for state: WatchStateSnapshot) {
        snapshotFreshnessTask?.cancel()
        let delay = state.generatedAt
            .addingTimeInterval(WatchStateSnapshot.staleAfter)
            .timeIntervalSinceNow
        guard delay > 0 else {
            isSnapshotStale = true
            return
        }

        isSnapshotStale = false
        snapshotFreshnessTask = Task { @MainActor [weak self] in
            do {
                try await Task.sleep(for: .seconds(delay))
            } catch {
                return
            }
            self?.isSnapshotStale = true
        }
    }

    func resumePendingCommands() {
        for command in pendingCommands {
            scheduleConfirmationTimeout(for: command)
            transmit(command)
        }
    }

    func recordConnectivityError(_ error: Error) {
        hasConnectivityError = true
        Self.logger.error(
            "Watch connectivity failed: \(error.localizedDescription, privacy: .private)"
        )
    }
}

extension WatchAppStore: WCSessionDelegate {
    nonisolated func session(
        _ session: WCSession,
        activationDidCompleteWith activationState: WCSessionActivationState,
        error: Error?
    ) {
        Task { @MainActor in
            if let error {
                recordConnectivityError(error)
            }
            isReachable = session.isReachable
            applyPayload(session.receivedApplicationContext)
            if activationState == .activated {
                resumePendingCommands()
            }
        }
    }

    nonisolated func sessionReachabilityDidChange(_ session: WCSession) {
        Task { @MainActor in
            isReachable = session.isReachable
            if session.isReachable {
                resumePendingCommands()
            }
        }
    }

    nonisolated func session(
        _ session: WCSession,
        didReceiveApplicationContext applicationContext: [String: Any]
    ) {
        Task { @MainActor in
            applyPayload(applicationContext)
        }
    }

    nonisolated func session(
        _ session: WCSession,
        didReceiveUserInfo userInfo: [String: Any] = [:]
    ) {
        Task { @MainActor in
            applyPayload(userInfo)
        }
    }

    nonisolated func session(_ session: WCSession, didReceiveMessage message: [String: Any]) {
        Task { @MainActor in
            applyPayload(message)
        }
    }

    nonisolated func session(
        _ session: WCSession,
        didReceiveMessage message: [String: Any],
        replyHandler: @escaping ([String: Any]) -> Void
    ) {
        Task { @MainActor in
            applyPayload(message)
            replyHandler(["received": true])
        }
    }
}
#endif
