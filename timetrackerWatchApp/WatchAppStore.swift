import Foundation
import Observation
import OSLog

@Observable
@MainActor
final class WatchAppStore: NSObject {
    var snapshot: WatchStateSnapshot = .empty
    var isReachable = false
    var hasReceivedSnapshot = false
    var commandQueue: WatchCommandQueueState {
        didSet {
            persistCommandQueue()
        }
    }

    var isSnapshotStale = false
    var hasConnectivityError = false

    var pendingCommands: [WatchTimerCommand] {
        commandQueue.pendingCommands
    }

    var failedCommands: [WatchFailedCommand] {
        commandQueue.failedCommands
    }

    @ObservationIgnored let defaults: UserDefaults
    @ObservationIgnored let deviceID: String
    @ObservationIgnored let confirmationTimeout: TimeInterval = 20
    @ObservationIgnored var confirmationTasks: [UUID: Task<Void, Never>] = [:]
    @ObservationIgnored var snapshotFreshnessTask: Task<Void, Never>?

    static let commandQueueKey = "watch.commandQueue.v2"
    static let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "me.mezorewww.timetracker.watchkitapp",
        category: "WatchConnectivity"
    )

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        deviceID = WatchDeviceIdentity.loadOrCreate(defaults: defaults)
        if let data = defaults.data(forKey: Self.commandQueueKey) {
            if data.count <= WatchTransportLimits.maximumQueueEncodedBytes,
               let restoredQueue = try? JSONDecoder().decode(WatchCommandQueueState.self, from: data),
               restoredQueue.isSafeForRestoration
            {
                commandQueue = restoredQueue
            } else {
                commandQueue = WatchCommandQueueState()
                defaults.removeObject(forKey: Self.commandQueueKey)
                Self.logger.error("Discarded an unreadable or unsafe watch command queue")
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
}
