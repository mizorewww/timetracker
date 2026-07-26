import Foundation

struct AnalyticsTimelineSnapshotService {
    func snapshot(
        segments: [TimeSegment],
        tasks: [TaskNode],
        sessions: [TimeSession],
        taskParentPathByID: [UUID: String],
        date: Date = Date(),
        now: Date = Date(),
        calendar: Calendar = .current,
        minimumLaneGap: TimeInterval = 60
    ) -> AnalyticsTimelineSnapshot {
        let dayInterval = calendar.dateInterval(of: .day, for: date)
            ?? DateInterval(start: calendar.startOfDay(for: date), duration: 86400)
        let seeds = presentationSeeds(
            segments: segments,
            tasks: tasks,
            sessions: sessions,
            taskParentPathByID: taskParentPathByID,
            visibleInterval: dayInterval,
            now: now
        )
        return snapshot(
            seeds: seeds,
            visibleInterval: dayInterval,
            minimumLaneGap: minimumLaneGap
        )
    }

    func presentationSeeds(
        segments: [TimeSegment],
        tasks: [TaskNode],
        sessions: [TimeSession],
        taskParentPathByID: [UUID: String],
        visibleInterval: DateInterval,
        now: Date
    ) -> [TimelinePresentationSeed] {
        let taskByID = tasks.latestByID()
        let sessionsByTaskID = Dictionary(grouping: sessions.deduplicatedByID(), by: \.taskID)
        return segments.visibleDeduplicatedByID().compactMap { segment -> TimelinePresentationSeed? in
            guard segment.deletedAt == nil,
                  let interval = TrackedTimePolicy.interval(
                      startedAt: segment.startedAt,
                      endedAt: segment.endedAt,
                      now: now,
                      clippedTo: visibleInterval
                  )
            else {
                return nil
            }
            let task = taskByID[segment.taskID]
            let fallbackTitle = sessionsByTaskID[segment.taskID]?.first?.titleSnapshot
                ?? AppStrings.localized("task.unavailable")
            return TimelinePresentationSeed(
                id: .trackedSegment(segment.id),
                subject: .task(segment.taskID),
                title: task?.title ?? fallbackTitle,
                path: task.map {
                    taskParentPathByID[$0.id] ?? AppStrings.rootTask
                } ?? AppStrings.localized("task.unavailable.path"),
                iconName: task?.iconName ?? "checkmark.circle",
                colorHex: task?.colorHex ?? "0A84FF",
                usesCurrentEndLabel: segment.endedAt.map { $0 > now } ?? true,
                interval: interval
            )
        }
        .sorted(by: Self.seedPrecedes)
    }

    func snapshot(
        seeds: [TimelinePresentationSeed],
        visibleInterval: DateInterval,
        minimumLaneGap: TimeInterval = 60
    ) -> AnalyticsTimelineSnapshot {
        let visibleSeeds = seeds.compactMap { seed -> TimelinePresentationSeed? in
            guard let interval = seed.interval.intersection(with: visibleInterval),
                  interval.duration > 0
            else {
                return nil
            }
            let durationIntervals = Self.mergedIntervals(
                seed.durationIntervals.compactMap {
                    $0.intersection(with: interval)
                }
            )
            guard durationIntervals.isEmpty == false else { return nil }
            return TimelinePresentationSeed(
                id: seed.id,
                subject: seed.subject,
                title: seed.title,
                path: seed.path,
                iconName: seed.iconName,
                colorHex: seed.colorHex,
                usesCurrentEndLabel: seed.usesCurrentEndLabel,
                interval: interval,
                durationIntervals: durationIntervals
            )
        }
        .sorted(by: Self.seedPrecedes)
        guard visibleSeeds.isEmpty == false else { return .empty }

        let layoutItems = visibleSeeds.map { seed in
            TimelineLayoutItem(
                id: seed.id,
                startedAt: seed.interval.start,
                endedAt: seed.interval.end
            )
        }
        let layout = TimelineLayoutEngine.layout(
            items: layoutItems,
            dayInterval: visibleInterval,
            minimumLaneGap: minimumLaneGap
        )
        let seedByID = Dictionary(uniqueKeysWithValues: visibleSeeds.map { ($0.id, $0) })
        let entries = layout.entries.enumerated().compactMap { index, layoutEntry -> AnalyticsTimelineEntry? in
            guard let seed = seedByID[layoutEntry.id] else { return nil }
            return AnalyticsTimelineEntry(
                id: seed.id,
                subject: seed.subject,
                title: seed.title,
                path: seed.path,
                iconName: seed.iconName,
                colorHex: seed.colorHex,
                usesCurrentEndLabel: seed.usesCurrentEndLabel,
                startedAt: layoutEntry.item.startedAt,
                endedAt: layoutEntry.item.endedAt,
                lane: layoutEntry.lane,
                labelIndex: index,
                interval: layoutEntry.item.interval,
                durationSeconds: max(
                    0,
                    Int(seed.durationIntervals.reduce(0.0) {
                        $0 + $1.duration
                    })
                )
            )
        }
        let compression = TimelineAxisCompression(
            displayInterval: layout.displayInterval,
            busyIntervals: layout.entries.map(\.item.interval)
        )

        return AnalyticsTimelineSnapshot(
            entries: entries,
            displayInterval: layout.displayInterval,
            axisCompression: compression
        )
    }

    private nonisolated static func seedPrecedes(
        _ lhs: TimelinePresentationSeed,
        _ rhs: TimelinePresentationSeed
    ) -> Bool {
        if lhs.interval.start != rhs.interval.start {
            return lhs.interval.start < rhs.interval.start
        }
        if lhs.interval.end != rhs.interval.end {
            return lhs.interval.end < rhs.interval.end
        }
        return lhs.id.stableSortKey < rhs.id.stableSortKey
    }

    private nonisolated static func mergedIntervals(
        _ intervals: [DateInterval]
    ) -> [DateInterval] {
        let sorted = intervals
            .filter { $0.duration > 0 }
            .sorted {
                if $0.start != $1.start {
                    return $0.start < $1.start
                }
                return $0.end < $1.end
            }
        guard var current = sorted.first else { return [] }
        var result: [DateInterval] = []
        for interval in sorted.dropFirst() {
            if interval.start <= current.end {
                current = DateInterval(
                    start: current.start,
                    end: max(current.end, interval.end)
                )
            } else {
                result.append(current)
                current = interval
            }
        }
        result.append(current)
        return result
    }
}
