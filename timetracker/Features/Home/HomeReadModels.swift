import Foundation

/// Today's data-revision half; see `TimeTrackerStore.todaySnapshot`.
struct TodayHomeContent {
    let activeSegments: [TimeSegment]
    let quickStartTasks: [TaskNode]
    let forecasts: [ForecastDisplayItem]
    let countdownEvents: [CountdownEvent]

    var hasSupportingContent: Bool {
        !forecasts.isEmpty || !countdownEvents.isEmpty
    }

    @MainActor
    init(
        store: TimeTrackerStore,
        quickStartLimit: Int = 4,
        forecastLimit: Int = 3
    ) {
        activeSegments = store.activeSegments

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
           let selected = store.forecastDisplayItem(for: selectedTaskID)
        {
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

struct WeeklyGrossTimeSnapshot {
    let interval: DateInterval
    let daily: [DailyAnalyticsPoint]
    let requiresLiveRefresh: Bool

    var totalGrossSeconds: Int {
        daily.reduce(0) { $0 + $1.grossSeconds }
    }

    var totalWallSeconds: Int {
        daily.reduce(0) { $0 + $1.wallSeconds }
    }

    var hasTrackedTime: Bool {
        daily.contains { $0.grossSeconds > 0 }
    }
}
