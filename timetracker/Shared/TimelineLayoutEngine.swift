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

struct TimelineOmittedGap: Identifiable, Equatable {
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

struct TimelineAxisCompression: Equatable {
    let displayInterval: DateInterval
    let omittedGaps: [TimelineOmittedGap]
    let compressedDuration: TimeInterval

    init(
        displayInterval: DateInterval,
        busyIntervals: [DateInterval],
        gapThreshold: TimeInterval = 60 * 60,
        gapPlaceholderDuration: TimeInterval = 15 * 60
    ) {
        self.displayInterval = displayInterval
        let merged = Self.mergedIntervals(busyIntervals, clippedTo: displayInterval)
        var gaps: [TimelineOmittedGap] = []
        var removedBefore: TimeInterval = 0

        for pair in zip(merged, merged.dropFirst()) {
            let gapStart = pair.0.end
            let gapEnd = pair.1.start
            let gapDuration = gapEnd.timeIntervalSince(gapStart)
            guard gapDuration > gapThreshold else { continue }

            let placeholder = min(max(60, gapPlaceholderDuration), gapDuration)
            let compressedStartOffset = gapStart.timeIntervalSince(displayInterval.start) - removedBefore
            gaps.append(
                TimelineOmittedGap(
                    start: gapStart,
                    end: gapEnd,
                    compressedStartOffset: compressedStartOffset,
                    compressedDuration: placeholder
                )
            )
            removedBefore += gapDuration - placeholder
        }

        self.omittedGaps = gaps
        self.compressedDuration = max(1, displayInterval.duration - gaps.reduce(0) { $0 + $1.omittedDuration })
    }

    func ratio(for date: Date) -> Double {
        compressedOffset(for: date) / compressedDuration
    }

    func ratio(forCompressedOffset offset: TimeInterval) -> Double {
        offset / compressedDuration
    }

    func isInsideOmittedGap(_ date: Date) -> Bool {
        omittedGaps.contains { date > $0.start && date < $0.end }
    }

    private func compressedOffset(for date: Date) -> TimeInterval {
        let clampedDate = min(max(date, displayInterval.start), displayInterval.end)
        var offset = clampedDate.timeIntervalSince(displayInterval.start)

        for gap in omittedGaps {
            if clampedDate < gap.start {
                break
            }

            if clampedDate <= gap.end {
                let progress = gap.duration > 0 ? clampedDate.timeIntervalSince(gap.start) / gap.duration : 0
                return gap.compressedStartOffset + progress * gap.compressedDuration
            }

            offset -= gap.omittedDuration
        }

        return offset
    }

    private static func mergedIntervals(_ intervals: [DateInterval], clippedTo displayInterval: DateInterval) -> [DateInterval] {
        let clipped = intervals.compactMap { interval -> DateInterval? in
            let start = max(interval.start, displayInterval.start)
            let end = min(interval.end, displayInterval.end)
            guard end > start else { return nil }
            return DateInterval(start: start, end: end)
        }
        .sorted { $0.start < $1.start }

        var merged: [DateInterval] = []
        for interval in clipped {
            guard let last = merged.last else {
                merged.append(interval)
                continue
            }

            if interval.start <= last.end {
                merged[merged.count - 1] = DateInterval(start: last.start, end: max(last.end, interval.end))
            } else {
                merged.append(interval)
            }
        }
        return merged
    }
}

enum TimelineLayoutEngine {
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
        guard let earliestStart = items.map(\.startedAt).min(),
              let latestEnd = items.map(\.endedAt).max() else {
            return dayInterval
        }

        let start = max(earliestStart, dayInterval.start)
        let end = min(latestEnd, dayInterval.end)

        guard end > start else {
            return dayInterval
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
