import Foundation

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
