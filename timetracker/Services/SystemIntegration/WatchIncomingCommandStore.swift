import Foundation

/// Persists commands after WatchConnectivity reports delivery but before the
/// application command handler is ready. Retaining this queue across process
/// termination closes the delivery/processing gap on the iPhone side.
struct WatchIncomingCommandStore {
    private let defaults: UserDefaults
    private let key: String

    init(
        defaults: UserDefaults = .standard,
        key: String = "watch.pendingIncomingCommands.v1"
    ) {
        self.defaults = defaults
        self.key = key
    }

    func load() -> [WatchTimerCommand] {
        guard let data = defaults.data(forKey: key) else { return [] }
        do {
            return try JSONDecoder().decode([WatchTimerCommand].self, from: data)
        } catch {
            defaults.removeObject(forKey: key)
            return []
        }
    }

    func save(_ commands: [WatchTimerCommand]) {
        guard commands.isEmpty == false else {
            defaults.removeObject(forKey: key)
            return
        }
        do {
            defaults.set(try JSONEncoder().encode(commands), forKey: key)
        } catch {
            // WatchTimerCommand is fully Codable. Keep any previous durable
            // value if an unexpected encoder failure occurs.
        }
    }
}
