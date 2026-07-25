import Foundation

extension TimeTrackerStore {
    func analyticsOverview(for range: AnalyticsRange, now: Date = Date()) -> AnalyticsOverview {
        analyticsSnapshot(for: range, now: now).overview
    }

    func dailyBreakdown(range: AnalyticsRange, now: Date = Date()) -> [DailyAnalyticsPoint] {
        analyticsSnapshot(for: range, now: now).daily
    }

    func hourlyBreakdown(for date: Date = Date(), now: Date = Date()) -> [HourlyAnalyticsPoint] {
        guard let interval = Calendar.current.dateInterval(of: .day, for: date) else { return [] }
        return analyticsEngine.hourlyBreakdown(
            segments: visibleSegments(overlapping: interval, now: now),
            date: date,
            now: now
        )
    }

    func taskBreakdown(range: AnalyticsRange, now: Date = Date()) -> [TaskAnalyticsPoint] {
        analyticsSnapshot(for: range, now: now).taskBreakdown
    }

    func overlapSegments(range: AnalyticsRange, now: Date = Date()) -> [OverlapAnalyticsPoint] {
        analyticsSnapshot(for: range, now: now).overlaps
    }

    func completedFocusRoundSegments(
        segmentIDs: [UUID]
    ) -> [TimeSegment] {
        if ledgerDomainStore.hasIndexedSegmentHistory {
            return segmentIDs.compactMap { segmentID in
                guard let segment = ledgerDomainStore.segment(for: segmentID),
                      segment.deletedAt == nil
                else {
                    return nil
                }
                return segment
            }
        }

        let fallbackByID = allSegments
            .visibleDeduplicatedByID()
            .reduce(into: [UUID: TimeSegment]()) { result, segment in
                result[segment.id] = segment
            }

        return segmentIDs.compactMap { segmentID in
            let segment = fallbackByID[segmentID]
            guard segment?.deletedAt == nil else { return nil }
            return segment
        }
    }
}
