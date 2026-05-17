import Foundation

nonisolated struct TimelineLayoutItem: Identifiable, Equatable {
    let id: UUID
    let startedAt: Date
    let endedAt: Date

    var interval: DateInterval {
        DateInterval(start: startedAt, end: endedAt)
    }
}

nonisolated struct TimelineLayoutEntry: Identifiable, Equatable {
    let item: TimelineLayoutItem
    let lane: Int

    var id: UUID { item.id }
}

nonisolated struct TimelineLayoutResult: Equatable {
    let displayInterval: DateInterval
    let entries: [TimelineLayoutEntry]

    var laneCount: Int {
        (entries.map(\.lane).max() ?? -1) + 1
    }
}

nonisolated struct TimelineOmittedGap: Identifiable, Equatable {
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
