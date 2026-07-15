import Foundation

nonisolated enum WidgetSnapshotStoreError: Error, Equatable, Sendable {
    case sharedContainerUnavailable
    case invalidSnapshot
}

nonisolated enum WidgetSnapshotLoadResult: Equatable, Sendable {
    case snapshot(WidgetSnapshot, freshness: WidgetSnapshotFreshness)
    case sharedContainerUnavailable
    case missing
    case corrupted
}

nonisolated enum WidgetTimelineReloadDecision: Equatable, Sendable {
    case after(Date)
    case never
}

nonisolated struct WidgetSnapshotTimelinePolicy: Sendable {
    static let minimumRetryDelay: TimeInterval = 60
    static let maximumRecoveryRetryDelay: TimeInterval = WidgetSnapshot.staleAfter

    func reloadDecision(
        for result: WidgetSnapshotLoadResult,
        at now: Date
    ) -> WidgetTimelineReloadDecision {
        guard WidgetSnapshotLimits.isFinite(now) else { return .never }
        switch result {
        case let .snapshot(snapshot, .current):
            let staleDate = snapshot.generatedAt.addingTimeInterval(WidgetSnapshot.staleAfter)
            return .after(max(staleDate, now.addingTimeInterval(Self.minimumRetryDelay)))
        case .snapshot(_, .stale):
            return .after(now.addingTimeInterval(Self.maximumRecoveryRetryDelay))
        case let .snapshot(snapshot, .clockAdjusted):
            let earliestRetry = now.addingTimeInterval(Self.minimumRetryDelay)
            let latestRetry = now.addingTimeInterval(Self.maximumRecoveryRetryDelay)
            let clockRecoveryDate = snapshot.generatedAt.addingTimeInterval(
                -WidgetSnapshotLimits.maximumFutureClockSkew
            )
            return .after(max(earliestRetry, min(clockRecoveryDate, latestRetry)))
        case .sharedContainerUnavailable, .missing, .corrupted:
            return .never
        }
    }
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
        guard snapshot.isStructurallyValid else {
            throw WidgetSnapshotStoreError.invalidSnapshot
        }
        let data = try encoder.encode(snapshot)
        guard data.count <= WidgetSnapshotLimits.maximumEncodedBytes else {
            throw WidgetSnapshotStoreError.invalidSnapshot
        }
        defaults.set(data, forKey: Self.snapshotKey)
    }

    func load(at now: Date = Date()) -> WidgetSnapshot? {
        guard case let .snapshot(snapshot, _) = loadResult(at: now) else { return nil }
        return snapshot
    }

    func loadResult(at now: Date = Date()) -> WidgetSnapshotLoadResult {
        guard let defaults else { return .sharedContainerUnavailable }
        guard defaults.object(forKey: Self.snapshotKey) != nil else { return .missing }
        guard let data = defaults.data(forKey: Self.snapshotKey),
              data.count <= WidgetSnapshotLimits.maximumEncodedBytes,
              let snapshot = try? decoder.decode(WidgetSnapshot.self, from: data),
              snapshot.isStructurallyValid else {
            return .corrupted
        }
        return .snapshot(snapshot, freshness: snapshot.freshness(at: now))
    }

    func clear() {
        defaults?.removeObject(forKey: Self.snapshotKey)
    }
}
