import Foundation
import Combine
import SwiftUI

#if canImport(WatchConnectivity)
import WatchConnectivity
#endif

@MainActor
final class WatchAppStore: NSObject, ObservableObject {
    @Published private(set) var snapshot: WatchStateSnapshot = .empty
    @Published private(set) var isReachable = false

    private let deviceID = "watch"

    func activate() {
        #if canImport(WatchConnectivity)
        guard WCSession.isSupported() else { return }
        let session = WCSession.default
        session.delegate = self
        session.activate()
        applyApplicationContext(session.receivedApplicationContext)
        isReachable = session.isReachable
        #endif
    }

    func startTask(taskID: UUID) {
        send(
            WatchTimerCommand(
                id: UUID(),
                type: .startTask,
                taskID: taskID,
                segmentID: nil,
                issuedAt: Date(),
                deviceID: deviceID
            )
        )
    }

    func stopTimer(segmentID: UUID) {
        send(
            WatchTimerCommand(
                id: UUID(),
                type: .stopSegment,
                taskID: nil,
                segmentID: segmentID,
                issuedAt: Date(),
                deviceID: deviceID
            )
        )
    }

    private func send(_ command: WatchTimerCommand) {
        #if canImport(WatchConnectivity)
        let payload = WatchConnectivityPayloadCodec.encode(command: command)
        let session = WCSession.default
        if session.activationState == .activated, session.isReachable {
            session.sendMessage(payload, replyHandler: nil) { [weak self] _ in
                self?.queue(payload, in: session)
            }
        } else {
            queue(payload, in: session)
        }
        #endif
    }

    #if canImport(WatchConnectivity)
    private func queue(_ payload: [String: Any], in session: WCSession) {
        session.transferUserInfo(payload)
        isReachable = session.isReachable
    }

    private func applyApplicationContext(_ context: [String: Any]) {
        guard let state = WatchConnectivityPayloadCodec.decodeState(from: context) else { return }
        snapshot = state
    }
    #endif
}

#if canImport(WatchConnectivity)
extension WatchAppStore: WCSessionDelegate {
    nonisolated func session(
        _ session: WCSession,
        activationDidCompleteWith activationState: WCSessionActivationState,
        error: Error?
    ) {
        Task { @MainActor in
            isReachable = session.isReachable
            applyApplicationContext(session.receivedApplicationContext)
        }
    }

    nonisolated func sessionReachabilityDidChange(_ session: WCSession) {
        Task { @MainActor in
            isReachable = session.isReachable
        }
    }

    nonisolated func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) {
        Task { @MainActor in
            applyApplicationContext(applicationContext)
        }
    }
}
#endif
