import Foundation

nonisolated enum WatchConnectivityDeliveryStatus: Equatable, Sendable {
    case unavailable
    case notActivated
    case notReachable
    case submitted
    case failed(String)
}

#if os(iOS) && canImport(WatchConnectivity)
import OSLog
import WatchConnectivity

/// Process-wide WatchConnectivity session owner.
///
/// Commands carry an idempotent ID and are processed by the currently attached
/// scene; if no scene is attached the legacy receipt acknowledges delivery and
/// the watch build retries. Terminal results travel through one durable
/// `transferUserInfo` payload plus the synchronous reply handler when present.
@MainActor
final class WatchConnectivityBridge: NSObject {
    static let shared = WatchConnectivityBridge()

    private static let logger = Logger(
        subsystem: AppIdentity.loggingSubsystem,
        category: "WatchConnectivity"
    )

    var commandHandler: ((WatchTimerCommand) -> WatchCommandResult)?

    private let session: WCSession?

    init(session: WCSession? = WCSession.isSupported() ? .default : nil) {
        self.session = session
        super.init()
    }

    func activateIfSupported() {
        guard let session else { return }
        session.delegate = self
        session.activate()
    }

    @discardableResult
    func updateApplicationContext(
        _ snapshot: WatchStateSnapshot
    ) -> WatchConnectivityDeliveryStatus {
        guard let session else { return .unavailable }
        guard session.activationState == .activated else { return .notActivated }
        do {
            try session.updateApplicationContext(
                WatchConnectivityPayloadCodec.encode(state: snapshot)
            )
            return .submitted
        } catch {
            let message = recordFailure(
                operation: "applicationContext",
                error: error
            )
            return .failed(message)
        }
    }

    @discardableResult
    func sendReachableMessage(
        _ snapshot: WatchStateSnapshot
    ) -> WatchConnectivityDeliveryStatus {
        guard let session else { return .unavailable }
        guard session.isReachable else { return .notReachable }
        session.sendMessage(
            WatchConnectivityPayloadCodec.encode(state: snapshot),
            replyHandler: nil,
            errorHandler: { [weak self] error in
                Task { @MainActor in
                    self?.recordFailure(
                        operation: "reachableMessage",
                        error: error
                    )
                }
            }
        )
        return .submitted
    }

    private func handle(
        _ payload: [String: Any],
        replyHandler: (([String: Any]) -> Void)? = nil
    ) {
        guard let command = WatchConnectivityPayloadCodec.decodeCommand(from: payload) else {
            replyHandler?(["received": false])
            return
        }
        guard let commandHandler else {
            // Older watch builds understand this receipt. Current builds keep the
            // command pending until it is retried or times out.
            replyHandler?(["received": true])
            return
        }
        let result = commandHandler(command)
        replyHandler?(WatchConnectivityPayloadCodec.encode(result: result))
        deliverDurableCommandResult(result)
    }

    /// `transferUserInfo` provides a durable terminal result even if the direct
    /// reply is lost while either device changes reachability.
    private func deliverDurableCommandResult(_ result: WatchCommandResult) {
        guard let session, session.isPaired, session.isWatchAppInstalled else { return }
        session.transferUserInfo(
            WatchConnectivityPayloadCodec.encode(result: result)
        )
    }

    @discardableResult
    private func recordFailure(
        operation: String,
        error: Error
    ) -> String {
        let message = error.localizedDescription
        Self.logger.error(
            "WatchConnectivity \(operation, privacy: .public) failed: \(message, privacy: .private)"
        )
        return message
    }
}

extension WatchConnectivityBridge: WCSessionDelegate {
    nonisolated func session(
        _: WCSession,
        activationDidCompleteWith _: WCSessionActivationState,
        error: Error?
    ) {
        guard let error else { return }
        Task { @MainActor [weak self] in
            self?.recordFailure(operation: "activation", error: error)
        }
    }

    nonisolated func sessionDidBecomeInactive(_: WCSession) {}

    nonisolated func sessionDidDeactivate(_ session: WCSession) {
        session.activate()
    }

    nonisolated func session(
        _: WCSession,
        didReceiveUserInfo userInfo: [String: Any] = [:]
    ) {
        Task { @MainActor [weak self] in
            self?.handle(userInfo)
        }
    }

    nonisolated func session(
        _: WCSession,
        didReceiveMessage message: [String: Any]
    ) {
        Task { @MainActor [weak self] in
            self?.handle(message)
        }
    }

    nonisolated func session(
        _: WCSession,
        didReceiveMessage message: [String: Any],
        replyHandler: @escaping ([String: Any]) -> Void
    ) {
        Task { @MainActor [weak self] in
            self?.handle(message, replyHandler: replyHandler)
        }
    }
}
#endif
