import Foundation

extension TodayActivityHeatmapSnapshotService {
    func weeks(
        valuesByDay: [Date: Int],
        referencesByDay: [Date: Int],
        defaultReferenceValue: Int,
        weekCount: Int,
        dateRange: ActivityHeatmapDateRange,
        calendar: Calendar
    ) -> [ActivityHeatmapWeek] {
        var result: [ActivityHeatmapWeek] = []
        result.reserveCapacity(weekCount)
        for weekIndex in 0 ..< weekCount {
            guard let weekStart = calendar.date(
                byAdding: .weekOfYear,
                value: weekIndex,
                to: dateRange.interval.start
            ) else {
                continue
            }
            let days = (0 ..< Self.daysPerWeek).compactMap { dayIndex in
                calendar.date(byAdding: .day, value: dayIndex, to: weekStart).map { date in
                    let day = calendar.startOfDay(for: date)
                    let isFuture = day > dateRange.today
                    let value = isFuture ? 0 : valuesByDay[day, default: 0]
                    let reference = referencesByDay[day] ?? defaultReferenceValue
                    return ActivityHeatmapDay(
                        date: day,
                        value: value,
                        referenceValue: reference,
                        intensity: isFuture
                            ? .none
                            : ActivityHeatmapIntensity(
                                value: value,
                                referenceValue: reference
                            ),
                        isFuture: isFuture,
                        isToday: day == dateRange.today
                    )
                }
            }
            result.append(ActivityHeatmapWeek(startDate: weekStart, days: days))
        }
        return result
    }

    func dateRange(
        period: ActivityHeatmapPeriod,
        now: Date,
        calendar: Calendar
    ) -> ActivityHeatmapDateRange {
        let today = calendar.startOfDay(for: now)
        let currentWeekStart = calendar.dateInterval(
            of: .weekOfYear,
            for: now
        )?.start ?? today
        let intervalStart = calendar.date(
            byAdding: .weekOfYear,
            value: -(period.weekCount - 1),
            to: currentWeekStart
        ) ?? currentWeekStart
        let intervalEnd = calendar.date(
            byAdding: .weekOfYear,
            value: 1,
            to: currentWeekStart
        ) ?? now
        return ActivityHeatmapDateRange(
            interval: DateInterval(start: intervalStart, end: intervalEnd),
            today: today
        )
    }
}
