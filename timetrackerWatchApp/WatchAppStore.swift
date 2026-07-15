import Foundation
import Observation
import OSLog

#if canImport(WatchConnectivity)
import WatchConnectivity
#endif

@Observable
@MainActor
final class WatchAppStore: NSObject {
    private(set) var snapshot: WatchStateSnapshot = .empty
    private(set) var isReachable = false
    private(set) var hasReceivedSnapshot = false
    private(set) var commandQueue: WatchCommandQueueState {
        didSet {
            persistCommandQueue()
        }
    }
    private(set) var isSnapshotStale = false
    private(set) var hasConnectivityError = false

    var pendingCommands: [WatchTimerCommand] {
        commandQueue.pendingCommands
    }

    var failedCommands: [WatchFailedCommand] {
        commandQueue.failedCommands
    }

    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let deviceID = "watch"
    @ObservationIgnored private let confirmationTimeout: TimeInterval = 20
    @ObservationIgnored private var confirmationTasks: [UUID: Task<Void, Never>] = [:]
    @ObservationIgnored private var snapshotFreshnessTask: Task<Void, Never>?

    private static let commandQueueKey = "watch.commandQueue.v2"
    private static let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "me.mezorewww.timetracker.watchkitapp",
        category: "WatchConnectivity"
    )

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let data = defaults.data(forKey: Self.commandQueueKey) {
            if data.count <= WatchTransportLimits.maximumQueueEncodedBytes,
               let restoredQueue = try? JSONDecoder().decode(WatchCommandQueueState.self, from: data),
               restoredQueue.isSafeForRestoration {
                commandQueue = restoredQueue
            } else {
                commandQueue = WatchCommandQueueState()
                defaults.removeObject(forKey: Self.commandQueueKey)
                Self.logger.error(
                    "Discarded an unreadable or unsafe watch command queue"
                )
            }
        } else {
            commandQueue = WatchCommandQueueState()
        }
        super.init()
    }

    deinit {
        for task in confirmationTasks.values {
            task.cancel()
        }
        snapshotFreshnessTask?.cancel()
    }

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

    func startTask(taskID: UUID) {
        submit(
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
        submit(
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

    func retryCommand(commandID: UUID) {
        guard let command = commandQueue.retry(commandID: commandID) else { return }
        scheduleConfirmationTimeout(for: command)
        transmit(command)
    }

    func discardCommand(commandID: UUID) {
        confirmationTasks[commandID]?.cancel()
        confirmationTasks[commandID] = nil
        commandQueue.discard(commandID: commandID)
    }

    private func submit(_ command: WatchTimerCommand) {
        commandQueue.enqueue(command)
        scheduleConfirmationTimeout(for: command)
        transmit(command)
    }

    private func scheduleConfirmationTimeout(for command: WatchTimerCommand) {
        confirmationTasks[command.id]?.cancel()
        let remaining = max(
            0,
            command.issuedAt.addingTimeInterval(confirmationTimeout).timeIntervalSinceNow
        )
        confirmationTasks[command.id] = Task { @MainActor [weak self] in
            do {
                try await Task.sleep(for: .seconds(remaining))
            } catch {
                return
            }
            guard let self,
                  commandQueue.pendingCommands.contains(where: { $0.id == command.id }) else {
                return
            }
            confirmationTasks[command.id] = nil
            _ = commandQueue.timeOut(commandID: command.id)
        }
    }

    private func persistCommandQueue() {
        guard !commandQueue.pendingCommands.isEmpty || !commandQueue.failedCommands.isEmpty else {
            defaults.removeObject(forKey: Self.commandQueueKey)
            return
        }
        guard commandQueue.isSafeForRestoration,
              let data = try? JSONEncoder().encode(commandQueue),
              data.count <= WatchTransportLimits.maximumQueueEncodedBytes else {
            defaults.removeObject(forKey: Self.commandQueueKey)
            Self.logger.error(
                "Could not persist an unsafe watch command queue"
            )
            return
        }
        defaults.set(data, forKey: Self.commandQueueKey)
    }

    #if canImport(WatchConnectivity)
    /// Every attempt is put on the durable user-info channel. A reachable
    /// message is an acceleration path, not the only copy of the command.
    private func transmit(_ command: WatchTimerCommand) {
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

    private func applyPayload(_ payload: [String: Any]) {
        if let result = WatchConnectivityPayloadCodec.decodeCommandResult(from: payload) {
            applyCommandResult(result)
            return
        }
        if let state = WatchConnectivityPayloadCodec.decodeState(from: payload) {
            applyState(state)
        }
    }

    private func applyCommandResult(_ result: WatchCommandResult) {
        guard commandQueue.resolve(result) != nil else { return }
        confirmationTasks[result.commandID]?.cancel()
        confirmationTasks[result.commandID] = nil
        hasConnectivityError = false
    }

    private func applyState(_ state: WatchStateSnapshot) {
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

    private func scheduleSnapshotFreshness(for state: WatchStateSnapshot) {
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

    private func resumePendingCommands() {
        for command in pendingCommands {
            scheduleConfirmationTimeout(for: command)
            transmit(command)
        }
    }

    private func recordConnectivityError(_ error: Error) {
        hasConnectivityError = true
        Self.logger.error(
            "Watch connectivity failed: \(error.localizedDescription, privacy: .private)"
        )
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
