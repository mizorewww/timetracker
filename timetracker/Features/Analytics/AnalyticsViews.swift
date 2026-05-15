import Combine
import SwiftUI

struct AnalyticsView: View {
    @ObservedObject var store: TimeTrackerStore
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @State private var range: AnalyticsRange = .today
    @State private var referenceDate = Date()
    @State private var now = Date()
    private let analyticsRefreshTimer = Timer.publish(every: 30, on: .main, in: .common).autoconnect()

    var body: some View {
        let snapshotDate = range.effectiveSnapshotDate(referenceDate: referenceDate, liveNow: now)
        let snapshot = store.analyticsSnapshot(for: range, now: snapshotDate)
        AnalyticsContent(
            store: store,
            snapshot: snapshot,
            range: $range,
            referenceDate: $referenceDate,
            now: now,
            horizontalSizeClass: horizontalSizeClass
        )
        .navigationTitle(AppStrings.analytics)
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .background(AppColors.background)
        .onReceive(analyticsRefreshTimer) { date in
            now = date
            if referenceDate > date {
                referenceDate = date
            }
        }
    }
}

private struct AnalyticsContent: View {
    @ObservedObject var store: TimeTrackerStore
    let snapshot: AnalyticsSnapshot
    @Binding var range: AnalyticsRange
    @Binding var referenceDate: Date
    let now: Date
    let horizontalSizeClass: UserInterfaceSizeClass?

    private var layout: AnalyticsLayoutPolicy {
        AnalyticsLayoutPolicy(horizontalSizeClass: horizontalSizeClass)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                AnalyticsHeader(range: $range, referenceDate: $referenceDate, now: now, layout: layout)
                AnalyticsDecisionSummaryGrid(snapshot: snapshot)
                AnalyticsMetricGrid(
                    overview: snapshot.overview,
                    comparison: snapshot.comparison,
                    rhythm: snapshot.rhythm
                )
                AnalyticsMetricGlossaryStrip()
                TaskForecastsCard(store: store)
                AnalyticsBreakdownSection(snapshot: snapshot)
                AnalyticsRangeSection(snapshot: snapshot, range: range)
                AnalyticsRhythmQualityGrid(rhythm: snapshot.rhythm, quality: snapshot.quality)
                AnalyticsOverlapCard(overlaps: snapshot.overlaps)
            }
            .padding()
        }
        .transaction { transaction in
            transaction.animation = nil
        }
    }
}
