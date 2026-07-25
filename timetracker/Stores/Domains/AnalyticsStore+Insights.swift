import Foundation

extension AnalyticsStore {
    func insights(
        overview: AnalyticsOverview,
        comparison: AnalyticsComparison,
        rhythm _: AnalyticsRhythm,
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
                ),
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
                severity: .neutral,
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
        }

        return Array(result.prefix(4))
    }

    func deltaText(_ seconds: Int) -> String {
        if seconds == 0 {
            return DurationFormatter.compact(0)
        }
        let prefix = seconds > 0 ? "+" : "-"
        return "\(prefix)\(DurationFormatter.compact(abs(seconds)))"
    }

    func comparisonBody(for comparison: AnalyticsComparison) -> String {
        let matchedProgress = comparison.window.basis == .matchedProgress
        if comparison.previousGrossSeconds == 0, comparison.currentGrossSeconds > 0 {
            return AppStrings.localized(
                matchedProgress
                    ? "analytics.insight.comparison.newMatchedBody"
                    : "analytics.insight.comparison.newCompleteBody"
            )
        }
        if abs(comparison.grossDeltaSeconds) < 10 * 60 {
            return AppStrings.localized(
                matchedProgress
                    ? "analytics.insight.comparison.steadyMatchedBody"
                    : "analytics.insight.comparison.steadyCompleteBody"
            )
        }
        if comparison.grossDeltaSeconds > 0 {
            return AppStrings.localized(
                matchedProgress
                    ? "analytics.insight.comparison.upMatchedBody"
                    : "analytics.insight.comparison.upCompleteBody"
            )
        }
        return AppStrings.localized(
            matchedProgress
                ? "analytics.insight.comparison.downMatchedBody"
                : "analytics.insight.comparison.downCompleteBody"
        )
    }

    func percentText(_ value: Double) -> String {
        "\(Int((value * 100).rounded()))%"
    }
}
