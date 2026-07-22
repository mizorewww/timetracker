import Foundation

nonisolated enum TimelineLayoutEngine {
    static func layout(
        items: [TimelineLayoutItem],
        dayInterval: DateInterval,
        minimumLaneGap: TimeInterval = 60
    ) -> TimelineLayoutResult {
        PerformanceSignpost.interval("Timeline layout") {
            layoutWithoutInstrumentation(
                items: items,
                dayInterval: dayInterval,
                minimumLaneGap: minimumLaneGap
            )
        }
    }

    private static func layoutWithoutInstrumentation(
        items: [TimelineLayoutItem],
        dayInterval: DateInterval,
        minimumLaneGap: TimeInterval
    ) -> TimelineLayoutResult {
        let visibleItems = items
            .compactMap { clippedItem($0, to: dayInterval) }
            .sorted {
                if $0.startedAt != $1.startedAt {
                    return $0.startedAt < $1.startedAt
                }
                if $0.endedAt != $1.endedAt {
                    return $0.endedAt < $1.endedAt
                }
                return $0.id.stableSortKey < $1.id.stableSortKey
            }

        let displayInterval = makeDisplayInterval(for: visibleItems, dayInterval: dayInterval)
        let itemByID = Dictionary(
            uniqueKeysWithValues: visibleItems.map { ($0.id, $0) }
        )
        let entries = TimelineLaneAllocator.assignments(
            for: visibleItems.map { item in
                TimelineLaneInterval(
                    id: item.id,
                    start: item.startedAt.timeIntervalSinceReferenceDate,
                    end: item.endedAt.timeIntervalSinceReferenceDate
                )
            },
            minimumGap: minimumLaneGap
        )
        .compactMap { assignment -> TimelineLayoutEntry? in
            guard let item = itemByID[assignment.id] else { return nil }
            return TimelineLayoutEntry(item: item, lane: assignment.lane)
        }

        return TimelineLayoutResult(displayInterval: displayInterval, entries: entries)
    }

    static func makeDisplayInterval(
        for items: [TimelineLayoutItem],
        dayInterval: DateInterval
    ) -> DateInterval {
        var earliestStart: Date?
        var latestEnd: Date?

        for item in items {
            earliestStart = earliestStart.map { min($0, item.startedAt) } ?? item.startedAt
            latestEnd = latestEnd.map { max($0, item.endedAt) } ?? item.endedAt
        }

        guard let earliestStart, let latestEnd else {
            return dayInterval
        }

        let start = max(earliestStart, dayInterval.start)
        let end = min(latestEnd, dayInterval.end)

        guard end > start else {
            return dayInterval
        }

        return DateInterval(start: start, end: end)
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
