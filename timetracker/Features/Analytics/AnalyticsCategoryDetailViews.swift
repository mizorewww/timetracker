import SwiftUI

struct AnalyticsCategoryDetailView: View {
    @ObservedObject var store: TimeTrackerStore
    let category: AnalyticsCategory
    @Binding var range: AnalyticsRange
    @Binding var referenceDate: Date
    let now: Date

    var body: some View {
        let snapshotDate = range.effectiveSnapshotDate(referenceDate: referenceDate, liveNow: now)
        let snapshot = store.analyticsSnapshot(for: range, now: snapshotDate)

        List {
            AnalyticsPeriodSection(range: $range, referenceDate: $referenceDate, liveNow: now)
            categoryContent(snapshot: snapshot)
        }
        #if os(iOS)
        .listStyle(.insetGrouped)
        #else
        .listStyle(.inset)
        #endif
        .scrollContentBackground(.hidden)
        .background(AppColors.background)
        .navigationTitle(category.title)
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .transaction { transaction in
            transaction.animation = nil
        }
    }

    @ViewBuilder
    private func categoryContent(snapshot: AnalyticsSnapshot) -> some View {
        switch category {
        case .overview:
            AnalyticsDetailSection(
                title: AppStrings.localized("analytics.summary.title"),
                subtitle: AppStrings.localized("analytics.category.overview.subtitle")
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
            if range == .today {
                AnalyticsDetailSection(
                    title: AppStrings.localized("analytics.hourDistribution.title"),
                    subtitle: AppStrings.localized("analytics.hourDistribution.subtitle")
                ) {
                    TodayActivityContent(activity: snapshot.todayActivity)
                }

                AnalyticsDetailSection(
                    title: AppStrings.localized("analytics.timeline.title"),
                    subtitle: AppStrings.localized("analytics.timeline.subtitle")
                ) {
                    OverlappingTimelineContent(timeline: snapshot.timeline)
                }
            } else {
                AnalyticsDetailSection(
                    title: AppStrings.localized("analytics.dailyTrend.title"),
                    subtitle: AppStrings.localized("analytics.dailyTrend.subtitle")
                ) {
                    DailyTrendContent(daily: snapshot.daily)
                }
            }

        case .tasks:
            AnalyticsDetailSection(
                title: AppStrings.localized("analytics.taskUsage.title"),
                subtitle: AppStrings.localized("analytics.taskUsage.subtitle")
            ) {
                TaskDonutContent(
                    tasks: snapshot.taskBreakdown,
                    totalSeconds: max(snapshot.overview.grossSeconds, 1)
                )
            }

            AnalyticsDetailSection(
                title: AppStrings.localized("analytics.rootUsage.title"),
                subtitle: AppStrings.localized("analytics.rootUsage.subtitle")
            ) {
                AnalyticsGroupBreakdownContent(
                    items: snapshot.rootBreakdown,
                    totalSeconds: max(snapshot.rootBreakdown.reduce(0) { $0 + $1.grossSeconds }, 1)
                )
            }

            AnalyticsDetailSection(
                title: AppStrings.localized("analytics.categoryUsage.title"),
                subtitle: AppStrings.localized("analytics.categoryUsage.subtitle")
            ) {
                AnalyticsGroupBreakdownContent(
                    items: snapshot.categoryBreakdown,
                    totalSeconds: max(snapshot.categoryBreakdown.reduce(0) { $0 + $1.grossSeconds }, 1)
                )
            }

        case .pomodoro:
            AnalyticsDetailSection(
                title: AppStrings.localized("analytics.category.pomodoro.title"),
                subtitle: AppStrings.localized("analytics.category.pomodoro.subtitle")
            ) {
                PomodoroLedgerContent(store: store)
            }

        case .decisions:
            AnalyticsDetailSection(
                title: AppStrings.localized("analytics.decisions.title"),
                subtitle: AppStrings.localized("analytics.decisions.subtitle")
            ) {
                AnalyticsInsightList(insights: snapshot.insights)
            }

            AnalyticsDetailSection(
                title: AppStrings.localized("analytics.forecasts.title"),
                subtitle: AppStrings.localized("analytics.forecasts.subtitle")
            ) {
                TaskForecastsContent(store: store)
            }

        case .quality:
            AnalyticsDetailSection(
                title: AppStrings.localized("analytics.rhythm.title"),
                subtitle: AppStrings.localized("analytics.rhythm.subtitle")
            ) {
                AnalyticsRhythmContent(rhythm: snapshot.rhythm)
            }

            AnalyticsDetailSection(
                title: AppStrings.localized("analytics.quality.title"),
                subtitle: AppStrings.localized("analytics.quality.subtitle")
            ) {
                AnalyticsQualityContent(quality: snapshot.quality)
            }

            AnalyticsDetailSection(
                title: AppStrings.localized("analytics.overlap.title"),
                subtitle: AppStrings.localized("analytics.overlap.subtitle")
            ) {
                AnalyticsOverlapContent(overlaps: snapshot.overlaps)
            }
        }
    }
}
