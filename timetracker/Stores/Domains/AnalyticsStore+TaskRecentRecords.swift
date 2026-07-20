import Foundation

extension AnalyticsStore {
    func recentRecords(
        segments: [TimeSegment],
        sessions: [TimeSession],
        tasks: [TaskNode],
        taskIDs: Set<UUID>,
        taskPathByID: [UUID: String],
        now: Date
    ) -> [TaskRecentRecordPoint] {
        let taskByID = tasks.latestByID()
        let sessionByID = Dictionary(uniqueKeysWithValues: sessions.deduplicatedByID().map { ($0.id, $0) })
        return segments.deduplicatedByID()
            .filter { taskIDs.contains($0.taskID) && $0.deletedAt == nil }
            .sorted {
                if $0.startedAt != $1.startedAt {
                    return $0.startedAt > $1.startedAt
                }
                return $0.id.uuidString < $1.id.uuidString
            }
            .prefix(LedgerStore.maximumRecentSegmentsPerTask)
            .map { segment in
                let task = taskByID[segment.taskID]
                return TaskRecentRecordPoint(
                    id: segment.id,
                    taskID: segment.taskID,
                    title: task?.title
                        ?? sessionByID[segment.sessionID]?.titleSnapshot
                        ?? AppStrings.localized("task.unavailable"),
                    path: task.flatMap { taskPathByID[$0.id] }
                        ?? AppStrings.localized("task.unavailable.path"),
                    startedAt: segment.startedAt,
                    endedAt: segment.endedAt,
                    durationSeconds: TrackedTimePolicy.elapsedSeconds(
                        startedAt: segment.startedAt,
                        endedAt: segment.endedAt,
                        now: now
                    )
                )
            }
    }

    func taskDayLabel(for date: Date, range: AnalyticsRange, calendar: Calendar) -> String {
        switch range {
        case .today:
            return DateFormatter.localizedString(from: date, dateStyle: .none, timeStyle: .short)
        case .week:
            let weekday = calendar.shortWeekdaySymbols[calendar.component(.weekday, from: date) - 1]
            return "\(weekday) \(calendar.component(.day, from: date))"
        case .month:
            return "\(calendar.component(.day, from: date))"
        }
    }
}
