import Foundation

nonisolated enum WidgetSnapshotStoreError: Error, Equatable, Sendable {
    case sharedContainerUnavailable
    case invalidSnapshot
}

nonisolated enum WidgetSnapshotLoadResult: Equatable, Sendable {
    case snapshot(WidgetSnapshot)
    case sharedContainerUnavailable
    case missing
    case corrupted
}

struct SharedWidgetSnapshotStore {
    static let suiteName = "group.me.mezorewww.timetracker"
    static let snapshotKey = "widget.activeTimerSnapshot.v1"
    static let widgetKind = "TimeTrackerActiveTimerWidget"

    var defaults: UserDefaults?
    var encoder: JSONEncoder = JSONEncoder()
    var decoder: JSONDecoder = JSONDecoder()

    init(defaults: UserDefaults? = UserDefaults(suiteName: Self.suiteName)) {
        self.defaults = defaults
    }

    var isAvailable: Bool {
        defaults != nil
    }

    func save(_ snapshot: WidgetSnapshot) throws {
        guard let defaults else {
            throw WidgetSnapshotStoreError.sharedContainerUnavailable
        }
        guard snapshot.isValid(at: Date()) else {
            throw WidgetSnapshotStoreError.invalidSnapshot
        }
        let data = try encoder.encode(snapshot)
        guard data.count <= WidgetSnapshotLimits.maximumEncodedBytes else {
            throw WidgetSnapshotStoreError.invalidSnapshot
        }
        defaults.set(data, forKey: Self.snapshotKey)
    }

    func load() -> WidgetSnapshot? {
        guard case let .snapshot(snapshot) = loadResult() else { return nil }
        return snapshot
    }

    func loadResult() -> WidgetSnapshotLoadResult {
        guard let defaults else { return .sharedContainerUnavailable }
        guard defaults.object(forKey: Self.snapshotKey) != nil else { return .missing }
        guard let data = defaults.data(forKey: Self.snapshotKey),
              data.count <= WidgetSnapshotLimits.maximumEncodedBytes,
              let snapshot = try? decoder.decode(WidgetSnapshot.self, from: data),
              snapshot.isValid(at: Date()) else {
            return .corrupted
        }
        return .snapshot(snapshot)
    }

    func clear() {
        defaults?.removeObject(forKey: Self.snapshotKey)
    }
}
