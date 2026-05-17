import Foundation

#if os(iOS) && canImport(WatchConnectivity)
import WatchConnectivity

@MainActor
final class WatchConnectivityBridge: NSObject {
    static let shared = WatchConnectivityBridge()

    var commandHandler: ((WatchTimerCommand) -> Void)?

    private let session: WCSession?

    init(session: WCSession? = WCSession.isSupported() ? .default : nil) {
        self.session = session
        super.init()
    }

    var isSupported: Bool {
        session != nil
    }

    func activateIfSupported() {
        guard let session else { return }
        session.delegate = self
        session.activate()
    }

    func updateApplicationContext(_ snapshot: WatchStateSnapshot) {
        guard let session, session.activationState == .activated else { return }
        try? session.updateApplicationContext(WatchConnectivityPayloadCodec.encode(state: snapshot))
    }

    func sendReachableMessage(_ snapshot: WatchStateSnapshot) {
        guard let session, session.isReachable else { return }
        session.sendMessage(WatchConnectivityPayloadCodec.encode(state: snapshot), replyHandler: nil)
    }

    private func handle(_ command: WatchTimerCommand) {
        commandHandler?(command)
    }
}

extension WatchConnectivityBridge: WCSessionDelegate {
    nonisolated func session(
        _ session: WCSession,
        activationDidCompleteWith activationState: WCSessionActivationState,
        error: Error?
    ) {}

    nonisolated func sessionDidBecomeInactive(_ session: WCSession) {}

    nonisolated func sessionDidDeactivate(_ session: WCSession) {
        session.activate()
    }

    nonisolated func session(
        _ session: WCSession,
        didReceiveUserInfo userInfo: [String: Any] = [:]
    ) {
        guard let command = WatchConnectivityPayloadCodec.decodeCommand(from: userInfo) else { return }
        Task { @MainActor [weak self, command] in
            self?.handle(command)
        }
    }

    nonisolated func session(
        _ session: WCSession,
        didReceiveMessage message: [String: Any]
    ) {
        guard let command = WatchConnectivityPayloadCodec.decodeCommand(from: message) else { return }
        Task { @MainActor [weak self, command] in
            self?.handle(command)
        }
    }

    nonisolated func session(
        _ session: WCSession,
        didReceiveMessage message: [String: Any],
        replyHandler: @escaping ([String: Any]) -> Void
    ) {
        guard let command = WatchConnectivityPayloadCodec.decodeCommand(from: message) else {
            replyHandler(["received": false])
            return
        }
        Task { @MainActor [weak self, command] in
            self?.handle(command)
        }
        replyHandler(["received": true])
    }
}
#endif
