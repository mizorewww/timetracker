import Foundation
import Observation
import OSLog

@Observable
@MainActor
final class WatchAppStore: NSObject {
    var snapshot: WatchStateSnapshot = .empty
    var isReachable = false
    var hasReceivedSnapshot = false
    var commandQueue = WatchCommandQueueState()

    var isSnapshotStale = false
    var hasConnectivityError = false

    var pendingCommands: [WatchTimerCommand] {
        commandQueue.pendingCommands
    }

    var failedCommands: [WatchFailedCommand] {
        commandQueue.failedCommands
    }

    @ObservationIgnored let deviceID: String
    @ObservationIgnored let confirmationTimeout: TimeInterval = 20
    @ObservationIgnored var confirmationTasks: [UUID: Task<Void, Never>] = [:]
    @ObservationIgnored var snapshotFreshnessTask: Task<Void, Never>?

    static let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "me.mezorewww.timetracker.watchkitapp",
        category: "WatchConnectivity"
    )

    init(defaults: UserDefaults = .standard) {
        deviceID = WatchDeviceIdentity.loadOrCreate(defaults: defaults)
        super.init()
    }

    deinit {
        for task in confirmationTasks.values {
            task.cancel()
        }
        snapshotFreshnessTask?.cancel()
    }
}
