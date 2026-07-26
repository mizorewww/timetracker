import SwiftUI

extension AnalyticsCategoryDetailView {
    @ViewBuilder
    func categoryContent(
        snapshot: AnalyticsSnapshot,
        displayedRange: AnalyticsRange,
        displayedReferenceDate: Date,
        isPlaceholder: Bool
    ) -> some View {
        switch category {
        case .overview:
            AnalyticsDetailSection(
                title: AppStrings.localized("analytics.summary.title"),
                subtitle: AppStrings.localized("analytics.category.overview.subtitle"),
                isPlaceholder: isPlaceholder
            ) {
                AnalyticsMetricList(
                    overview: snapshot.overview,
                    comparison: snapshot.comparison,
                    rhythm: snapshot.rhythm
                )
            }
            AnalyticsDetailSection(
                title: AppStrings.localized("analytics.glossary.title"),
                subtitle: nil
            ) {
                AnalyticsGlossaryList()
            }
        case .time:
            if displayedRange == .today {
                AnalyticsDetailSection(
                    title: AppStrings.localized("analytics.hourDistribution.title"),
                    subtitle: AppStrings.localized("analytics.hourDistribution.subtitle"),
                    isPlaceholder: isPlaceholder
                ) {
                    TodayActivityContent(activity: snapshot.todayActivity)
                }
                AnalyticsDetailSection(
                    title: AppStrings.localized("analytics.timeline.title"),
                    subtitle: AppStrings.localized("analytics.timeline.subtitle"),
                    isPlaceholder: isPlaceholder
                ) {
                    OverlappingTimelineContent(timeline: snapshot.timeline)
                }
                .accessibilityIdentifier("analytics.timeline.section")
            } else {
                AnalyticsDetailSection(
                    title: AppStrings.localized("analytics.dailyTrend.title"),
                    subtitle: AppStrings.localized("analytics.dailyTrend.subtitle"),
                    isPlaceholder: isPlaceholder
                ) {
                    DailyTrendContent(daily: snapshot.daily)
                }
            }
        case .tasks:
            AnalyticsDetailSection(
                title: AppStrings.localized("analytics.categoryUsage.title"),
                subtitle: AppStrings.localized("analytics.categoryUsage.subtitle"),
                headerIdentifier: "analytics.categoryUsage.header",
                isPlaceholder: isPlaceholder
            ) {
                AnalyticsGroupBreakdownContent(
                    items: snapshot.categoryBreakdown,
                    totalSeconds: snapshot.categoryBreakdown.reduce(0) {
                        $0 + $1.grossSeconds
                    }
                )
            }
            AnalyticsDetailSection(
                title: AppStrings.localized("analytics.taskUsage.title"),
                subtitle: AppStrings.localized("analytics.taskUsage.subtitle"),
                isPlaceholder: isPlaceholder
            ) {
                TaskDonutContent(
                    tasks: snapshot.taskBreakdown,
                    totalSeconds: snapshot.overview.grossSeconds
                )
            }
            AnalyticsDetailSection(
                title: AppStrings.localized("analytics.rootUsage.title"),
                subtitle: AppStrings.localized("analytics.rootUsage.subtitle"),
                isPlaceholder: isPlaceholder
            ) {
                AnalyticsGroupBreakdownContent(
                    items: snapshot.rootBreakdown,
                    totalSeconds: snapshot.rootBreakdown.reduce(0) {
                        $0 + $1.grossSeconds
                    }
                )
            }
        case .pomodoro:
            AnalyticsDetailSection(
                title: AppStrings.localized("analytics.category.pomodoro.title"),
                subtitle: AppStrings.localized("analytics.category.pomodoro.subtitle"),
                isPlaceholder: isPlaceholder
            ) {
                AnalyticsFocusRoundsContent(
                    store: store,
                    segmentIDs: snapshot.completedFocusRoundSegmentIDs
                )
            }
        case .decisions:
            AnalyticsDetailSection(
                title: AppStrings.localized("analytics.decisions.title"),
                subtitle: AppStrings.localized("analytics.decisions.subtitle"),
                isPlaceholder: isPlaceholder
            ) {
                AnalyticsInsightList(insights: snapshot.insights)
            }
            if displayedRange.isCurrentPeriod(displayedReferenceDate, liveNow: liveNow) {
                AnalyticsDetailSection(
                    title: AppStrings.localized("analytics.forecasts.title"),
                    subtitle: AppStrings.localized("analytics.forecasts.subtitle"),
                    isPlaceholder: isPlaceholder
                ) {
                    TaskForecastsContent(store: store)
                }
            }
        case .quality:
            AnalyticsDetailSection(
                title: AppStrings.localized("analytics.rhythm.title"),
                subtitle: AppStrings.localized("analytics.rhythm.subtitle"),
                isPlaceholder: isPlaceholder
            ) {
                AnalyticsRhythmContent(rhythm: snapshot.rhythm)
            }
            AnalyticsDetailSection(
                title: AppStrings.localized("analytics.quality.title"),
                subtitle: AppStrings.localized("analytics.quality.subtitle"),
                isPlaceholder: isPlaceholder
            ) {
                AnalyticsQualityContent(quality: snapshot.quality)
            }
            AnalyticsDetailSection(
                title: AppStrings.localized("analytics.overlap.title"),
                subtitle: AppStrings.localized("analytics.overlap.subtitle"),
                isPlaceholder: isPlaceholder
            ) {
                AnalyticsOverlapContent(overlaps: snapshot.overlaps)
            }
        }
    }
}
