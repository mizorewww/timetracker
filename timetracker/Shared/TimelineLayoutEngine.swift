import Foundation

struct TimelineLayoutItem: Identifiable, Equatable {
    let id: UUID
    let startedAt: Date
    let endedAt: Date

    var interval: DateInterval {
        DateInterval(start: startedAt, end: endedAt)
    }
}

struct TimelineLayoutEntry: Identifiable, Equatable {
    let item: TimelineLayoutItem
    let lane: Int

    var id: UUID { item.id }
}

struct TimelineLayoutResult: Equatable {
    let displayInterval: DateInterval
    let entries: [TimelineLayoutEntry]

    var laneCount: Int {
        (entries.map(\.lane).max() ?? -1) + 1
    }
}

enum TimelineLayoutEngine {
    static let minimumDisplayDuration: TimeInterval = 2 * 60 * 60
    static let leadingPadding: TimeInterval = 30 * 60

    static func layout(
        items: [TimelineLayoutItem],
        dayInterval: DateInterval,
        minimumLaneGap: TimeInterval = 60
    ) -> TimelineLayoutResult {
        let visibleItems = items
            .compactMap { clippedItem($0, to: dayInterval) }
            .sorted {
                if $0.startedAt == $1.startedAt {
                    return $0.endedAt < $1.endedAt
                }
                return $0.startedAt < $1.startedAt
            }

        let displayInterval = makeDisplayInterval(for: visibleItems, dayInterval: dayInterval)
        var laneEnds: [Date] = []
        var entries: [TimelineLayoutEntry] = []

        for item in visibleItems {
            let lane = firstAvailableLane(
                startingAt: item.startedAt,
                laneEnds: laneEnds,
                minimumLaneGap: minimumLaneGap
            ) ?? laneEnds.count

            if lane == laneEnds.count {
                laneEnds.append(item.endedAt)
            } else {
                laneEnds[lane] = item.endedAt
            }

            entries.append(TimelineLayoutEntry(item: item, lane: lane))
        }

        return TimelineLayoutResult(displayInterval: displayInterval, entries: entries)
    }

    static func makeDisplayInterval(
        for items: [TimelineLayoutItem],
        dayInterval: DateInterval
    ) -> DateInterval {
        guard !items.isEmpty else {
            return dayInterval
        }

        let earliest = items.map(\.startedAt).min() ?? dayInterval.start
        let latest = items.map(\.endedAt).max() ?? dayInterval.end
        let start = max(dayInterval.start, earliest.addingTimeInterval(-leadingPadding))
        var end = min(dayInterval.end, latest)

        if end.timeIntervalSince(start) < minimumDisplayDuration {
            end = min(dayInterval.end, start.addingTimeInterval(minimumDisplayDuration))
        }

        if end <= start {
            end = min(dayInterval.end, start.addingTimeInterval(60 * 60))
        }

        return DateInterval(start: start, end: end)
    }

    private static func firstAvailableLane(
        startingAt start: Date,
        laneEnds: [Date],
        minimumLaneGap: TimeInterval
    ) -> Int? {
        laneEnds.firstIndex { laneEnd in
            start.timeIntervalSince(laneEnd) > minimumLaneGap
        }
    }

    private static func clippedItem(
        _ item: TimelineLayoutItem,
        to dayInterval: DateInterval
    ) -> TimelineLayoutItem? {
        guard item.endedAt > dayInterval.start, item.startedAt < dayInterval.end else {
            return nil
        }

        let start = max(item.startedAt, dayInterval.start)
        let end = min(item.endedAt, dayInterval.end)
        guard end > start else { return nil }

        return TimelineLayoutItem(id: item.id, startedAt: start, endedAt: end)
    }
}
