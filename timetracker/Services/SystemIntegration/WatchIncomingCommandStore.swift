import Foundation

/// Persists commands after WatchConnectivity reports delivery but before the
/// application command handler is ready. Retaining this queue across process
/// termination closes the delivery/processing gap on the iPhone side.
struct WatchIncomingCommandStore {
    private let defaults: UserDefaults
    private let key: String

    init(
        defaults: UserDefaults = AppDefaults.shared,
        key: String = "watch.pendingIncomingCommands.v1"
    ) {
        self.defaults = defaults
        self.key = key
    }

    func load() -> [WatchTimerCommand] {
        guard let data = defaults.data(forKey: key) else { return [] }
        guard data.count <= WatchTransportLimits.maximumQueueEncodedBytes,
              let commands = try? JSONDecoder().decode([WatchTimerCommand].self, from: data),
              commands.count <= WatchTransportLimits.maximumIncomingCommands,
              commands.allSatisfy(\.isStructurallyValid),
              Set(commands.map(\.id)).count == commands.count
        else {
            defaults.removeObject(forKey: key)
            return []
        }
        return commands
    }

    func save(_ commands: [WatchTimerCommand]) {
        guard commands.isEmpty == false else {
            defaults.removeObject(forKey: key)
            return
        }
        guard commands.count <= WatchTransportLimits.maximumIncomingCommands,
              commands.allSatisfy(\.isStructurallyValid),
              Set(commands.map(\.id)).count == commands.count,
              let data = try? JSONEncoder().encode(commands),
              data.count <= WatchTransportLimits.maximumQueueEncodedBytes
        else {
            // Preserve the previous durable value if a caller hands this store
            // a queue that cannot be restored safely.
            return
        }
        defaults.set(data, forKey: key)
    }
}
