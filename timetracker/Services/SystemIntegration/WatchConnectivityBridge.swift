import Foundation

nonisolated enum WatchConnectivityOperation: String, Equatable, Sendable {
    case activation
    case applicationContext
    case reachableMessage
    case commandResultDelivery
}

nonisolated enum WatchConnectivityDeliveryStatus: Equatable, Sendable {
    case unavailable
    case notActivated
    case notReachable
    case submitted
    case failed(String)
}

nonisolated struct WatchConnectivityDiagnostic: Equatable, Sendable {
    var operation: WatchConnectivityOperation
    var message: String
}

#if os(iOS) && canImport(WatchConnectivity)
import OSLog
import WatchConnectivity

@MainActor
final class WatchConnectivityBridge: NSObject {
    static let shared = WatchConnectivityBridge()

    private static let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "me.mezorewww.timetracker",
        category: "WatchConnectivity"
    )

    var commandHandler: ((WatchTimerCommand) -> WatchCommandResult)? {
        didSet {
            drainPendingCommandsIfPossible()
        }
    }
    var diagnosticHandler: ((WatchConnectivityDiagnostic) -> Void)?
    private(set) var lastDiagnostic: WatchConnectivityDiagnostic?

    private let session: WCSession?
    private let pendingCommandStore: WatchIncomingCommandStore
    private var pendingCommands: [WatchTimerCommand]
    private let pendingCommandLimit = 64

    init(
        session: WCSession? = WCSession.isSupported() ? .default : nil,
        diagnosticHandler: ((WatchConnectivityDiagnostic) -> Void)? = nil,
        pendingCommandStore: WatchIncomingCommandStore = WatchIncomingCommandStore()
    ) {
        self.session = session
        self.diagnosticHandler = diagnosticHandler
        self.pendingCommandStore = pendingCommandStore
        self.pendingCommands = pendingCommandStore.load()
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
            let diagnostic = recordFailure(operation: .applicationContext, error: error)
            return .failed(diagnostic.message)
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
                    self?.recordFailure(operation: .reachableMessage, error: error)
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
        let overflowedCommands = enqueuePendingCommand(command)
        for overflowedCommand in overflowedCommands {
            deliverDurableCommandResult(
                .failed(
                    commandID: overflowedCommand.id,
                    failureCode: "queueOverflow"
                ),
                sendReachableMessage: true
            )
        }
        guard let commandHandler else {
            // Older watch builds understand this receipt. Current builds keep the
            // action pending until the queued command later receives a typed result.
            replyHandler?(["received": true])
            return
        }
        processPending(command, using: commandHandler, replyHandler: replyHandler)
    }

    private func drainPendingCommandsIfPossible() {
        guard let commandHandler, pendingCommands.isEmpty == false else { return }
        let commands = pendingCommands
        for command in commands where pendingCommands.contains(where: { $0.id == command.id }) {
            processPending(command, using: commandHandler, replyHandler: nil)
        }
    }

    private func processPending(
        _ command: WatchTimerCommand,
        using commandHandler: (WatchTimerCommand) -> WatchCommandResult,
        replyHandler: (([String: Any]) -> Void)?
    ) {
        let result = commandHandler(command)
        replyHandler?(WatchConnectivityPayloadCodec.encode(result: result))
        deliverDurableCommandResult(result, sendReachableMessage: replyHandler == nil)
        removePendingCommand(id: command.id)
    }

    @discardableResult
    private func enqueuePendingCommand(_ command: WatchTimerCommand) -> [WatchTimerCommand] {
        pendingCommands.removeAll { $0.id == command.id }
        pendingCommands.append(command)
        let overflowCount = max(0, pendingCommands.count - pendingCommandLimit)
        let overflowedCommands = Array(pendingCommands.prefix(overflowCount))
        if overflowCount > 0 {
            pendingCommands.removeFirst(overflowCount)
        }
        pendingCommandStore.save(pendingCommands)
        return overflowedCommands
    }

    private func removePendingCommand(id: UUID) {
        pendingCommands.removeAll { $0.id == id }
        pendingCommandStore.save(pendingCommands)
    }

    /// `transferUserInfo` provides a durable terminal result even if the direct
    /// reply is lost while either device changes reachability.
    private func deliverDurableCommandResult(
        _ result: WatchCommandResult,
        sendReachableMessage: Bool
    ) {
        guard let session, session.isPaired, session.isWatchAppInstalled else { return }
        let payload = WatchConnectivityPayloadCodec.encode(result: result)
        session.transferUserInfo(payload)
        guard sendReachableMessage, session.isReachable else { return }
        session.sendMessage(
            payload,
            replyHandler: nil,
            errorHandler: { [weak self] error in
                Task { @MainActor in
                    self?.recordFailure(operation: .commandResultDelivery, error: error)
                }
            }
        )
    }

    @discardableResult
    private func recordFailure(
        operation: WatchConnectivityOperation,
        error: Error
    ) -> WatchConnectivityDiagnostic {
        let diagnostic = WatchConnectivityDiagnostic(
            operation: operation,
            message: error.localizedDescription
        )
        lastDiagnostic = diagnostic
        diagnosticHandler?(diagnostic)
        Self.logger.error(
            "WatchConnectivity \(operation.rawValue, privacy: .public) failed: \(diagnostic.message, privacy: .private)"
        )
        return diagnostic
    }
}

extension WatchConnectivityBridge: WCSessionDelegate {
    nonisolated func session(
        _ session: WCSession,
        activationDidCompleteWith activationState: WCSessionActivationState,
        error: Error?
    ) {
        guard let error else { return }
        Task { @MainActor [weak self] in
            self?.recordFailure(operation: .activation, error: error)
        }
    }

    nonisolated func sessionDidBecomeInactive(_ session: WCSession) {}

    nonisolated func sessionDidDeactivate(_ session: WCSession) {
        session.activate()
    }

    nonisolated func session(
        _ session: WCSession,
        didReceiveUserInfo userInfo: [String: Any] = [:]
    ) {
        Task { @MainActor [weak self] in
            self?.handle(userInfo)
        }
    }

    nonisolated func session(
        _ session: WCSession,
        didReceiveMessage message: [String: Any]
    ) {
        Task { @MainActor [weak self] in
            self?.handle(message)
        }
    }

    nonisolated func session(
        _ session: WCSession,
        didReceiveMessage message: [String: Any],
        replyHandler: @escaping ([String: Any]) -> Void
    ) {
        Task { @MainActor [weak self] in
            self?.handle(message, replyHandler: replyHandler)
        }
    }
}
#endif
