import Foundation

extension AnalyticsStore {
    func comparison(
        segments: [TimeSegment],
        range: AnalyticsRange,
        taskIDs: Set<UUID>? = nil,
        now: Date,
        calendar: Calendar
    ) -> AnalyticsComparison {
        guard let currentInterval = analyticsInterval(for: range, now: now, calendar: calendar) else {
            return AnalyticsComparison(
                currentGrossSeconds: 0,
                previousGrossSeconds: 0,
                currentWallSeconds: 0,
                previousWallSeconds: 0
            )
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
        segments: [TimeSegment],
        range: AnalyticsRange,
        currentInterval: DateInterval,
        taskIDs: Set<UUID>? = nil,
        evaluatedAt cutoff: Date,
        calendar: Calendar
    ) -> AnalyticsComparison {
        guard let previousInterval = previousDecisionInterval(
            for: range,
            currentInterval: currentInterval,
            calendar: calendar
        ) else {
            return AnalyticsComparison(
                currentGrossSeconds: 0,
                previousGrossSeconds: 0,
                currentWallSeconds: 0,
                previousWallSeconds: 0
            )
        }

        let canonicalSegments = segments.deduplicatedByID()
        return AnalyticsComparison(
            currentGrossSeconds: seconds(
                in: currentInterval,
                segments: canonicalSegments,
                taskIDs: taskIDs,
                mode: .gross,
                now: cutoff
            ),
            previousGrossSeconds: seconds(
                in: previousInterval,
                segments: canonicalSegments,
                taskIDs: taskIDs,
                mode: .gross,
                now: cutoff
            ),
            currentWallSeconds: seconds(
                in: currentInterval,
                segments: canonicalSegments,
                taskIDs: taskIDs,
                mode: .wallClock,
                now: cutoff
            ),
            previousWallSeconds: seconds(
                in: previousInterval,
                segments: canonicalSegments,
                taskIDs: taskIDs,
                mode: .wallClock,
                now: cutoff
            )
        )
    }

    func rhythm(
        segments: [TimeSegment],
        range: AnalyticsRange,
        taskIDs: Set<UUID>? = nil,
        now: Date,
        calendar: Calendar
    ) -> AnalyticsRhythm {
        guard let interval = analyticsInterval(for: range, now: now, calendar: calendar) else {
            return emptyRhythm
        }
        return rhythm(
            segments: segments.deduplicatedByID(),
            interval: interval,
            taskIDs: taskIDs,
            now: now,
            calendar: calendar
        )
    }

    func quality(
        segments: [TimeSegment],
        range: AnalyticsRange,
        taskIDs: Set<UUID>? = nil,
        now: Date,
        calendar: Calendar
    ) -> AnalyticsQuality {
        guard let interval = analyticsInterval(for: range, now: now, calendar: calendar) else {
            return emptyQuality
        }
        return quality(
            segments: segments.deduplicatedByID(),
            interval: interval,
            taskIDs: taskIDs,
            now: now
        )
    }

    func insights(
        overview: AnalyticsOverview,
        comparison: AnalyticsComparison,
        rhythm: AnalyticsRhythm,
        quality: AnalyticsQuality,
        taskBreakdown: [TaskAnalyticsPoint]
    ) -> [AnalyticsInsight] {
        guard overview.grossSeconds > 0 else {
            return [
                AnalyticsInsight(
                    id: "no-data",
                    title: AppStrings.localized("analytics.insight.noData.title"),
                    value: DurationFormatter.compact(0),
                    body: AppStrings.localized("analytics.insight.noData.body"),
                    severity: .neutral,
                    taskID: nil
                )
            ]
        }

        var result: [AnalyticsInsight] = []
        if let topTask = taskBreakdown.first {
            let percent = Int((Double(topTask.grossSeconds) / Double(max(overview.grossSeconds, 1))) * 100)
            result.append(
                AnalyticsInsight(
                    id: "top-task",
                    title: AppStrings.localized("analytics.insight.topTask.title"),
                    value: topTask.title,
                    body: String(
                        format: AppStrings.localized("analytics.insight.topTask.bodyFormat"),
                        DurationFormatter.compact(topTask.grossSeconds),
                        percent
                    ),
                    severity: .neutral,
                    taskID: topTask.taskID
                )
            )
        }

        result.append(
            AnalyticsInsight(
                id: "comparison",
                title: AppStrings.localized("analytics.insight.comparison.title"),
                value: deltaText(comparison.grossDeltaSeconds),
                body: comparisonBody(for: comparison),
                severity: comparison.grossDeltaSeconds >= 0 ? .neutral : .positive,
                taskID: nil
            )
        )

        if quality.overlapRatio >= 0.15 {
            result.append(
                AnalyticsInsight(
                    id: "quality-overlap",
                    title: AppStrings.localized("analytics.insight.quality.title"),
                    value: percentText(quality.overlapRatio),
                    body: AppStrings.localized("analytics.insight.quality.overlapBody"),
                    severity: quality.overlapRatio >= 0.3 ? .critical : .warning,
                    taskID: nil
                )
            )
        } else if quality.shortSegmentRatio >= 0.35 {
            result.append(
                AnalyticsInsight(
                    id: "quality-fragmented",
                    title: AppStrings.localized("analytics.insight.quality.title"),
                    value: percentText(quality.shortSegmentRatio),
                    body: AppStrings.localized("analytics.insight.quality.fragmentedBody"),
                    severity: .warning,
                    taskID: nil
                )
            )
        } else {
            result.append(
                AnalyticsInsight(
                    id: "quality-steady",
                    title: AppStrings.localized("analytics.insight.quality.title"),
                    value: DurationFormatter.compact(rhythm.longestContinuousSeconds),
                    body: AppStrings.localized("analytics.insight.quality.steadyBody"),
                    severity: .positive,
                    taskID: nil
                )
            )
        }

        if let nextTask = taskBreakdown.first {
            result.append(
                AnalyticsInsight(
                    id: "next-action",
                    title: AppStrings.localized("analytics.insight.next.title"),
                    value: nextTask.title,
                    body: AppStrings.localized("analytics.insight.next.body"),
                    severity: .neutral,
                    taskID: nextTask.taskID
                )
            )
        }

        return Array(result.prefix(4))
    }
}
