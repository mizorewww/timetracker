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
            guard let resolvedSnapshot = await store.loadAnalyticsSnapshot(
                for: range,
                evaluation: evaluation
            ) else {
                return
            }
            snapshot = resolvedSnapshot
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
        .navigationTitle(category.destinationTitle)
        .accessibilityIdentifier("analytics.categoryDetail.\(category.rawValue)")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .transaction { transaction in
            transaction.animation = nil
        }
    }

}
