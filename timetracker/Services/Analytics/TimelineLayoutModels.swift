import Foundation

nonisolated enum TimelineEntryID: Hashable, Sendable {
    case trackedSegment(UUID)
    case appleHealthWorkout(UUID)
    case appleHealthSleep(UUID)

    var namespace: String {
        switch self {
        case .trackedSegment:
            "trackedSegment"
        case .appleHealthWorkout:
            "appleHealthWorkout"
        case .appleHealthSleep:
            "appleHealthSleep"
        }
    }

    var uuid: UUID {
        switch self {
        case let .trackedSegment(id),
             let .appleHealthWorkout(id),
             let .appleHealthSleep(id):
            id
        }
    }

    var namespacedKey: String {
        "\(namespace).\(uuid.uuidString)"
    }

    var stableSortKey: String {
        switch self {
        case let .trackedSegment(id):
            "0|\(id.uuidString)"
        case let .appleHealthWorkout(id):
            "1|\(id.uuidString)"
        case let .appleHealthSleep(anchorSampleID):
            "2|\(anchorSampleID.uuidString)"
        }
    }
}

nonisolated struct TimelineLayoutItem: Identifiable, Equatable, Sendable {
    let id: TimelineEntryID
    let startedAt: Date
    let endedAt: Date

    init(id: TimelineEntryID, startedAt: Date, endedAt: Date) {
        self.id = id
        self.startedAt = startedAt
        self.endedAt = endedAt
    }

    init(id: UUID, startedAt: Date, endedAt: Date) {
        self.init(
            id: .trackedSegment(id),
            startedAt: startedAt,
            endedAt: endedAt
        )
    }

    var interval: DateInterval {
        DateInterval(start: startedAt, end: endedAt)
    }
}

nonisolated struct TimelineLayoutEntry: Identifiable, Equatable, Sendable {
    let item: TimelineLayoutItem
    let lane: Int

    var id: TimelineEntryID {
        item.id
    }
}

nonisolated struct TimelineLayoutResult: Equatable, Sendable {
    let displayInterval: DateInterval
    let entries: [TimelineLayoutEntry]

    var laneCount: Int {
        (entries.map(\.lane).max() ?? -1) + 1
    }
}

nonisolated struct TimelineOmittedGap: Identifiable, Equatable, Sendable {
    let start: Date
    let end: Date
    let compressedStartOffset: TimeInterval
    let compressedDuration: TimeInterval

    var id: String {
        "\(start.timeIntervalSince1970)-\(end.timeIntervalSince1970)"
    }

    var duration: TimeInterval {
        end.timeIntervalSince(start)
    }

    var omittedDuration: TimeInterval {
        max(0, duration - compressedDuration)
    }

    var compressedMidpointOffset: TimeInterval {
        compressedStartOffset + compressedDuration / 2
    }
}
