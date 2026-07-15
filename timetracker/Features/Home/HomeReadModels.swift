import Foundation

struct TodayHomeContent {
    let activeSegments: [TimeSegment]
    let quickStartTasks: [TaskNode]
    let forecasts: [ForecastDisplayItem]
    let timelineSegments: [TimeSegment]
    let countdownEvents: [CountdownEvent]

    @MainActor
    init(
        store: TimeTrackerStore,
        quickStartLimit: Int = 4,
        forecastLimit: Int = 3
    ) {
        activeSegments = store.activeSegments
        timelineSegments = store.timelineSegments

        let pinnedTasks = store.preferences.quickStartTaskIDs
            .compactMap { store.task(for: $0) }
            .filter(store.isTaskAvailableForTracking)
            .deduplicatedByID()
        let recentTasks = store.frequentRecentTasks(
            excluding: Set(pinnedTasks.map(\.id)),
            limit: max(0, quickStartLimit - pinnedTasks.count)
        )
        quickStartTasks = Array(
            (pinnedTasks + recentTasks)
                .deduplicatedByID()
                .prefix(max(0, quickStartLimit))
        )

        let candidates = store.forecastDisplayItems()
        if let selectedTaskID = store.selectedTaskID,
           let selected = store.forecastDisplayItem(for: selectedTaskID) {
            forecasts = Array(
                ([selected] + candidates.filter { $0.taskID != selected.taskID })
                    .prefix(max(0, forecastLimit))
            )
        } else {
            forecasts = Array(candidates.prefix(max(0, forecastLimit)))
        }

        countdownEvents = Self.sortedCountdownEvents(store.countdownEvents)
    }

    static func sortedCountdownEvents(_ events: [CountdownEvent]) -> [CountdownEvent] {
        events.sorted { lhs, rhs in
            if lhs.date != rhs.date {
                return lhs.date < rhs.date
            }
            let titleComparison = lhs.title.localizedStandardCompare(rhs.title)
            if titleComparison != .orderedSame {
                return titleComparison == .orderedAscending
            }
            return lhs.id.uuidString < rhs.id.uuidString
        }
    }
}

nonisolated struct TodayMetricsSnapshot: Equatable, Sendable {
    let grossSeconds: Int
    let wallSeconds: Int
    let previousGrossSeconds: Int
    let previousWallSeconds: Int
}

nonisolated enum TodayMetricTrend: Equatable, Sendable {
    case noComparison
    case increased(percent: Int)
    case decreased(percent: Int)
    case unchanged

    init(current: Int, previous: Int) {
        guard previous > 0 else {
            self = .noComparison
            return
        }

        let percentage = ((Double(max(0, current)) / Double(previous)) - 1) * 100
        let boundedPercentage = min(Double(Int.max), max(Double(Int.min + 1), percentage.rounded()))
        let rounded = Int(boundedPercentage)
        if rounded > 0 {
            self = .increased(percent: rounded)
        } else if rounded < 0 {
            self = .decreased(percent: abs(rounded))
        } else {
            self = .unchanged
        }
    }
}

extension TimeTrackerStore {
    func todayMetricsSnapshot(
        now: Date,
        calendar: Calendar = .current
    ) -> TodayMetricsSnapshot {
        guard let todayInterval = calendar.dateInterval(of: .day, for: now),
              let previousDate = calendar.date(byAdding: .day, value: -1, to: now),
              let previousInterval = calendar.dateInterval(of: .day, for: previousDate) else {
            return TodayMetricsSnapshot(
                grossSeconds: 0,
                wallSeconds: 0,
                previousGrossSeconds: 0,
                previousWallSeconds: 0
            )
        }

        let combinedInterval = DateInterval(start: previousInterval.start, end: todayInterval.end)
        let segments = visibleSegments(overlapping: combinedInterval, now: now)
        let taskIDs = Set(segments.map(\.taskID))

        func seconds(in interval: DateInterval, mode: AggregationMode) -> Int {
            ledgerSummaryService.secondsInInterval(
                taskIDs: taskIDs,
                segments: segments,
                interval: interval,
                mode: mode,
                now: now
            )
        }

        return TodayMetricsSnapshot(
            grossSeconds: seconds(in: todayInterval, mode: .gross),
            wallSeconds: seconds(in: todayInterval, mode: .wallClock),
            previousGrossSeconds: seconds(in: previousInterval, mode: .gross),
            previousWallSeconds: seconds(in: previousInterval, mode: .wallClock)
        )
    }
}
