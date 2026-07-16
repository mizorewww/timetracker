import Foundation

extension LedgerStore {
    static let maximumIndexedDayCount = 366

    func segmentIDs(overlapping intervals: [DateInterval], now: Date) -> Set<UUID> {
        intervals.reduce(into: Set<UUID>()) { result, interval in
            if exceedsDayIndexLimit(interval, calendar: segmentIndexCalendar) {
                for (id, snapshot) in segmentSnapshotByID
                    where snapshot.overlaps(interval, at: now) {
                    result.insert(id)
                }
                return
            }
            for id in longSpanSegmentIDs {
                guard segmentSnapshotByID[id]?.overlaps(interval, at: now) == true else {
                    continue
                }
                result.insert(id)
            }
            for day in dayKeys(overlapping: interval, calendar: segmentIndexCalendar) {
                for id in segmentIDsByDay[day] ?? [] {
                    guard segmentSnapshotByID[id]?.overlaps(interval, at: now) == true else {
                        continue
                    }
                    result.insert(id)
                }
            }
        }
    }

    func exceedsDayIndexLimit(
        _ interval: DateInterval,
        calendar: Calendar
    ) -> Bool {
        let firstDay = calendar.startOfDay(for: interval.start)
        guard let exclusiveLimit = calendar.date(
            byAdding: .day,
            value: Self.maximumIndexedDayCount,
            to: firstDay
        ) else {
            return true
        }
        return interval.end > exclusiveLimit
    }
}
