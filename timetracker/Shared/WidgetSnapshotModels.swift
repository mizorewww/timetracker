import Foundation

struct WidgetSnapshot: Codable, Equatable {
    var generatedAt: Date
    var todayGrossSeconds: Int
    var todayWallSeconds: Int
    var activeTimers: [WidgetTimerSnapshot]
    var recentTasks: [WidgetRecentTaskSnapshot] = []

    static var empty: WidgetSnapshot {
        WidgetSnapshot(
            generatedAt: Date(),
            todayGrossSeconds: 0,
            todayWallSeconds: 0,
            activeTimers: [],
            recentTasks: []
        )
    }
}

struct WidgetTimerSnapshot: Codable, Equatable, Identifiable {
    var id: UUID
    var taskID: UUID
    var title: String
    var path: String
    var startedAt: Date
    var colorHex: String?
    var iconName: String?
}

struct WidgetRecentTaskSnapshot: Codable, Equatable, Identifiable {
    var taskID: UUID
    var title: String
    var path: String
    var colorHex: String?
    var iconName: String?

    var id: UUID { taskID }
}

enum WidgetSnapshotStoreError: Error, Equatable {
    case sharedContainerUnavailable
}

struct SharedWidgetSnapshotStore {
    static let suiteName = "group.me.mezorewww.timetracker"
    static let snapshotKey = "widget.activeTimerSnapshot.v1"

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
        let data = try encoder.encode(snapshot)
        defaults.set(data, forKey: Self.snapshotKey)
    }

    func load() -> WidgetSnapshot? {
        guard let defaults else { return nil }
        guard let data = defaults.data(forKey: Self.snapshotKey) else { return nil }
        return try? decoder.decode(WidgetSnapshot.self, from: data)
    }

    func clear() {
        defaults?.removeObject(forKey: Self.snapshotKey)
    }
}
