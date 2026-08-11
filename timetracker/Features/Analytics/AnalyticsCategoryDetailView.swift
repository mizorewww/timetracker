import SwiftUI

struct AnalyticsCategoryDetailView: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    let store: TimeTrackerStore
    let category: AnalyticsCategory
    @Binding var range: AnalyticsRange
    @Binding var referenceDate: Date
    let liveNow: Date
    @Binding var monthNavigationAnchor: AnalyticsMonthNavigationAnchor?
    @State private var loadedPresentation: AnalyticsLoadedSnapshot?

    var body: some View {
        let evaluation = range.evaluation(referenceDate: referenceDate, liveNow: liveNow)
        let request = AnalyticsSnapshotRequest(
            range: range,
            evaluation: evaluation,
            revision: store.analyticsRevision,
            liveRefreshBucket: store.analyticsLiveRefreshBucket(for: evaluation)
        )
        let exactCachedPresentation = store.cachedAnalyticsSnapshot(
            for: range,
            evaluation: evaluation
        ).map {
            AnalyticsLoadedSnapshot(snapshot: $0, request: request)
        }
        let displayedPresentation = exactCachedPresentation ?? loadedPresentation
        let presentationPhase = AnalyticsSnapshotPresentationPhase.resolve(
            loadedRequest: displayedPresentation?.request,
            currentRequest: request
        )

        List {
            AnalyticsPeriodSection(
                range: $range,
                referenceDate: $referenceDate,
                liveNow: liveNow,
                monthNavigationAnchor: $monthNavigationAnchor,
                isRefreshing: presentationPhase.isRefreshing
            )
            if let displayedPresentation {
                categoryContent(
                    snapshot: displayedPresentation.snapshot,
                    displayedRange: displayedPresentation.request.range,
                    displayedReferenceDate:
                    displayedPresentation.request.evaluationKey.interval.start,
                    isPlaceholder: presentationPhase.obscuresLoadedMetrics
                )
            } else {
                ProgressView()
                    .frame(maxWidth: .infinity, minHeight: 160)
                    .accessibilityLabel(AppStrings.localized("analytics.loading"))
                    .accessibilityIdentifier("analytics.detail.initialLoading")
            }
        }
        .task(id: request) {
            if let cachedSnapshot = store.cachedAnalyticsSnapshot(
                for: range,
                evaluation: evaluation
            ) {
                guard Task.isCancelled == false else { return }
                loadedPresentation = AnalyticsLoadedSnapshot(
                    snapshot: cachedSnapshot,
                    request: request
                )
                return
            }
            await Task.yield()
            guard Task.isCancelled == false else { return }
            guard let resolvedSnapshot = await store.loadAnalyticsSnapshot(
                for: range,
                evaluation: evaluation
            ) else {
                return
            }
            guard Task.isCancelled == false else { return }
            loadedPresentation = AnalyticsLoadedSnapshot(
                snapshot: resolvedSnapshot,
                request: request
            )
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
