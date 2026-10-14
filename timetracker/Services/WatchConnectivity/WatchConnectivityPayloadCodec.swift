import Foundation

/// WatchConnectivity dictionaries carry one JSON-encoded value under a kind
/// tag. Decoding re-validates the value, because the payload crosses devices.
enum WatchConnectivityPayloadCodec {
    private nonisolated static let kindKey = "kind"
    private nonisolated static let valueKey = "value"
    private nonisolated static let commandKind = "timerCommand"
    private nonisolated static let commandResultKind = "commandResult"
    private nonisolated static let stateKind = "stateSnapshot"

    nonisolated static func encode(command: WatchTimerCommand) -> [String: Any] {
        payload(kind: commandKind, value: command)
    }

    nonisolated static func encode(result: WatchCommandResult) -> [String: Any] {
        payload(kind: commandResultKind, value: result)
    }

    nonisolated static func encode(state: WatchStateSnapshot) -> [String: Any] {
        payload(kind: stateKind, value: state)
    }

    nonisolated static func decodeCommand(from payload: [String: Any]) -> WatchTimerCommand? {
        decode(WatchTimerCommand.self, kind: commandKind, from: payload)
            .flatMap { $0.isStructurallyValid ? $0 : nil }
    }

    nonisolated static func decodeCommandResult(from payload: [String: Any]) -> WatchCommandResult? {
        decode(WatchCommandResult.self, kind: commandResultKind, from: payload)
            .flatMap { $0.isValid(at: Date()) ? $0 : nil }
    }

    nonisolated static func decodeState(from payload: [String: Any]) -> WatchStateSnapshot? {
        decode(WatchStateSnapshot.self, kind: stateKind, from: payload)
            .flatMap { snapshot in
                guard snapshot.activeTimers.count <= WatchTransportLimits.maximumActiveTimers,
                      snapshot.recentTasks.count <= WatchTransportLimits.maximumRecentTasks,
                      snapshot.isValid(at: Date())
                else { return nil }
                return snapshot
            }
    }

    private nonisolated static func payload(kind: String, value: some Encodable) -> [String: Any] {
        // The value types are plain Codable structs; encoding cannot fail.
        let data = (try? JSONEncoder().encode(value)) ?? Data()
        return [kindKey: kind, valueKey: data]
    }

    private nonisolated static func decode<Value: Decodable>(
        _: Value.Type,
        kind: String,
        from payload: [String: Any]
    ) -> Value? {
        guard payload[kindKey] as? String == kind,
              let data = payload[valueKey] as? Data
        else { return nil }
        return try? JSONDecoder().decode(Value.self, from: data)
    }
}
