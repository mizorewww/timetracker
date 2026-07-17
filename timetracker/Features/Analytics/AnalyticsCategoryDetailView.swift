import SwiftUI

struct AnalyticsCategoryDetailView: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    let store: TimeTrackerStore
    let category: AnalyticsCategory
    @Binding var range: AnalyticsRange
    @Binding var referenceDate: Date
    let liveNow: Date
    @Binding var monthNavigationAnchor: AnalyticsMonthNavigationAnchor?
    @State private var snapshot: AnalyticsSnapshot?
    @State private var loadedRequest: AnalyticsSnapshotRequest?

    var body: some View {
        let evaluation = range.evaluation(referenceDate: referenceDate, liveNow: liveNow)
        let request = AnalyticsSnapshotRequest(
            range: range,
            evaluation: evaluation,
            revision: store.analyticsRevision,
            liveRefreshBucket: store.analyticsLiveRefreshBucket(for: evaluation)
        )
        let canKeepDisplayingSnapshot = loadedRequest.map {
            $0.canRemainVisible(whileLoading: request)
        } ?? false

        List {
            AnalyticsPeriodSection(
                range: $range,
                referenceDate: $referenceDate,
                liveNow: liveNow,
                monthNavigationAnchor: $monthNavigationAnchor,
                isRefreshing: loadedRequest != request
            )
            if let snapshot, canKeepDisplayingSnapshot {
                categoryContent(snapshot: snapshot)
            } else {
                ProgressView()
                    .frame(maxWidth: .infinity, minHeight: 160)
                    .accessibilityLabel(AppStrings.localized("analytics.loading"))
            }
        }
        .task(id: request) {
            await Task.yield()
            guard Task.isCancelled == false else { return }
            snapshot = store.analyticsSnapshot(for: range, evaluation: evaluation)
            guard Task.isCancelled == false else { return }
            loadedRequest = request
        }
        #if os(iOS)
        .listStyle(.insetGrouped)
        #else
        .listStyle(.inset)
        #endif
        .contentMargins(
            .bottom,
            dynamicTypeSize.isAccessibilitySize ? 112 : 16,
            for: .scrollContent
        )
        .scrollContentBackground(.hidden)
        .background(AppColors.background)
        .navigationTitle(category.title)
        .accessibilityIdentifier("analytics.categoryDetail.\(category.rawValue)")
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
                    totalSeconds: snapshot.overview.grossSeconds
                )
            }
            AnalyticsDetailSection(
                title: AppStrings.localized("analytics.rootUsage.title"),
                subtitle: AppStrings.localized("analytics.rootUsage.subtitle")
            ) {
                AnalyticsGroupBreakdownContent(
                    items: snapshot.rootBreakdown,
                    totalSeconds: snapshot.rootBreakdown.reduce(0) { $0 + $1.grossSeconds }
                )
            }
            AnalyticsDetailSection(
                title: AppStrings.localized("analytics.categoryUsage.title"),
                subtitle: AppStrings.localized("analytics.categoryUsage.subtitle")
            ) {
                AnalyticsGroupBreakdownContent(
                    items: snapshot.categoryBreakdown,
                    totalSeconds: snapshot.categoryBreakdown.reduce(0) { $0 + $1.grossSeconds }
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
