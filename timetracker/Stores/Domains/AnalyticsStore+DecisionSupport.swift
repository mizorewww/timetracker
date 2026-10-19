import Foundation

nonisolated extension AnalyticsStore {
    func comparison(
        segments: [AnalyticsSegmentRecord],
        range: AnalyticsRange,
        taskIDs: Set<UUID>? = nil,
        now: Date,
        calendar: Calendar
    ) -> AnalyticsComparison {
        guard let currentInterval = analyticsInterval(for: range, now: now, calendar: calendar) else {
            return emptyComparison(at: now)
        }

        return comparison(
            segments: segments,
            range: range,
            currentInterval: currentInterval,
            taskIDs: taskIDs,
            evaluatedAt: now,
            calendar: calendar
        )
    }

    func comparison(
        segments: [AnalyticsSegmentRecord],
        range: AnalyticsRange,
        currentInterval: DateInterval,
        taskIDs: Set<UUID>? = nil,
        evaluatedAt cutoff: Date,
        calendar: Calendar
    ) -> AnalyticsComparison {
        guard let window = comparisonWindow(
            for: range,
            currentInterval: currentInterval,
            evaluatedAt: cutoff,
            calendar: calendar
        ) else {
            return emptyComparison(at: cutoff)
        }

        let canonicalSegments = segments.deduplicatedByID()
        return AnalyticsComparison(
            window: window,
            currentGrossSeconds: seconds(
                in: window.current,
                segments: canonicalSegments,
                taskIDs: taskIDs,
                mode: .gross,
                now: window.current.end
            ),
            previousGrossSeconds: seconds(
                in: window.previous,
                segments: canonicalSegments,
                taskIDs: taskIDs,
                mode: .gross,
                now: window.previous.end
            ),
            currentWallSeconds: seconds(
                in: window.current,
                segments: canonicalSegments,
                taskIDs: taskIDs,
                mode: .wallClock,
                now: window.current.end
            ),
            previousWallSeconds: seconds(
                in: window.previous,
                segments: canonicalSegments,
                taskIDs: taskIDs,
                mode: .wallClock,
                now: window.previous.end
            )
        )
    }

    private func emptyComparison(at date: Date) -> AnalyticsComparison {
        let emptyWindow = DateInterval(start: date, duration: 0)
        return AnalyticsComparison(
            window: AnalyticsComparisonWindow(
                current: emptyWindow,
                previous: emptyWindow,
                basis: .matchedProgress
            ),
            currentGrossSeconds: 0,
            previousGrossSeconds: 0,
            currentWallSeconds: 0,
            previousWallSeconds: 0
        )
    }
}
