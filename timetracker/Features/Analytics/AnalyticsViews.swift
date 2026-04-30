import Combine
import SwiftUI

struct AnalyticsView: View {
    @ObservedObject var store: TimeTrackerStore
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @State private var range: AnalyticsRange = .today
    @State private var now = Date()
    private let analyticsRefreshTimer = Timer.publish(every: 30, on: .main, in: .common).autoconnect()

    var body: some View {
        Group {
            if let snapshot = store.cachedAnalyticsSnapshot(for: range) {
                AnalyticsContent(
                    store: store,
                    snapshot: snapshot,
                    range: $range,
                    now: now,
                    horizontalSizeClass: horizontalSizeClass
                )
            } else {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .navigationTitle(AppStrings.analytics)
        .background(AppColors.background)
        .task(id: range) {
            store.refreshAnalyticsSnapshot(for: range, now: now)
        }
        .onReceive(analyticsRefreshTimer) { date in
            now = date
            store.refreshAnalyticsSnapshot(for: range, now: date)
        }
    }
}

private struct AnalyticsContent: View {
    @ObservedObject var store: TimeTrackerStore
    let snapshot: AnalyticsSnapshot
    @Binding var range: AnalyticsRange
    let now: Date
    let horizontalSizeClass: UserInterfaceSizeClass?

    private var layout: AnalyticsLayoutPolicy {
        AnalyticsLayoutPolicy(horizontalSizeClass: horizontalSizeClass)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                AnalyticsHeader(range: $range, layout: layout)
                AnalyticsMetricGrid(overview: snapshot.overview)
                TaskForecastsCard(store: store)
                AnalyticsRangeSection(store: store, snapshot: snapshot, range: range, now: now)
                AnalyticsOverlapCard(overlaps: snapshot.overlaps)
            }
            .padding()
        }
    }
}
