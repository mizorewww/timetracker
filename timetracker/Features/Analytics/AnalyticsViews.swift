import SwiftUI

struct AnalyticsView: View {
    let store: TimeTrackerStore
    @State private var range: AnalyticsRange = .today
    @State private var referenceDate = Date()
    @State private var snapshot: AnalyticsSnapshot?
    @State private var loadedRequest: AnalyticsSnapshotRequest?
    @State private var followsCurrentPeriod = true
    var body: some View {
        TimelineView(.periodic(from: .now, by: 30)) { context in
            let effectiveReferenceDate = followsCurrentPeriod ? context.date : referenceDate
            let snapshotDate = range.effectiveSnapshotDate(referenceDate: effectiveReferenceDate, liveNow: context.date)
            let request = AnalyticsSnapshotRequest(range: range, referenceDate: effectiveReferenceDate,
                revision: store.analyticsRevision, liveRefreshBucket: store.analyticsLiveRefreshBucket(for: range, now: snapshotDate))
            let effectiveReferenceDateBinding = Binding(
                get: { followsCurrentPeriod ? context.date : referenceDate },
                set: { newDate in
                    referenceDate = newDate
                    followsCurrentPeriod = range.isCurrentPeriod(newDate, liveNow: context.date)
                }
            )
            Group {
                if let snapshot, loadedRequest == request {
                    AnalyticsContent(
                        store: store,
                        snapshot: snapshot,
                        range: $range,
                        referenceDate: effectiveReferenceDateBinding,
                        liveNow: context.date
                    )
                } else {
                    ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
                        .accessibilityLabel(AppStrings.localized("analytics.loading"))
                }
            }
            .task(id: request) {
                snapshot = store.analyticsSnapshot(for: range, now: snapshotDate)
                loadedRequest = request
            }
        }
        .navigationTitle(AppStrings.analytics)
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .accessibilityIdentifier("analytics.view")
        .background(AppColors.background)
        .onChange(of: range) { _, range in
            guard followsCurrentPeriod == false else { return }
            followsCurrentPeriod = range.isCurrentPeriod(referenceDate, liveNow: Date())
        }
    }
}

private struct AnalyticsContent: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    let store: TimeTrackerStore
    let snapshot: AnalyticsSnapshot
    @Binding var range: AnalyticsRange
    @Binding var referenceDate: Date
    let liveNow: Date

    var body: some View {
        List {
            AnalyticsPeriodSection(range: $range, referenceDate: $referenceDate, liveNow: liveNow)

            Section {
                AnalyticsHomeSummaryRow(snapshot: snapshot)
            } header: {
                Text(AppStrings.localized("analytics.summary.title"))
            } footer: {
                Text(
                    String(
                        format: AppStrings.localized("analytics.summary.periodFootnote"),
                        AnalyticsPeriodText.title(for: range, date: referenceDate)
                    )
                )
            }

            Section {
                ForEach(AnalyticsCategory.allCases) { category in
                    NavigationLink {
                        AnalyticsCategoryDetailView(
                            store: store,
                            category: category,
                            range: $range,
                            referenceDate: $referenceDate
                        )
                    } label: {
                        AnalyticsCategoryRow(category: category, snapshot: snapshot)
                    }
                }
            } header: {
                Text(AppStrings.localized("analytics.categories.title"))
            } footer: {
                Text(AppStrings.localized("analytics.categories.footer"))
            }
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
        .accessibilityIdentifier("analytics.view")
        .transaction { transaction in
            transaction.animation = nil
        }
    }

}

private struct AnalyticsCategoryDetailView: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    let store: TimeTrackerStore
    let category: AnalyticsCategory
    @Binding var range: AnalyticsRange
    @Binding var referenceDate: Date
    @State private var snapshot: AnalyticsSnapshot?
    @State private var loadedRequest: AnalyticsSnapshotRequest?

    var body: some View {
        TimelineView(.periodic(from: .now, by: 30)) { context in
            let snapshotDate = range.effectiveSnapshotDate(referenceDate: referenceDate, liveNow: context.date)
            let request = AnalyticsSnapshotRequest(range: range, referenceDate: referenceDate,
                revision: store.analyticsRevision, liveRefreshBucket: store.analyticsLiveRefreshBucket(for: range, now: snapshotDate))
            List {
                AnalyticsPeriodSection(range: $range, referenceDate: $referenceDate, liveNow: context.date)
                if let snapshot, loadedRequest == request {
                    categoryContent(snapshot: snapshot)
                } else {
                    ProgressView().frame(maxWidth: .infinity, minHeight: 160)
                        .accessibilityLabel(AppStrings.localized("analytics.loading"))
                }
            }
            .task(id: request) {
                snapshot = store.analyticsSnapshot(for: range, now: snapshotDate)
                loadedRequest = request
            }
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
