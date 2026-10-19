import SwiftUI

struct AnalyticsCategoryDetailView: View {
    let store: TimeTrackerStore
    let category: AnalyticsCategory
    @Binding var range: AnalyticsRange
    @Binding var referenceDate: Date
    let liveNow: Date
    @Binding var monthNavigationAnchor: AnalyticsMonthNavigationAnchor?
    @State private var loadedPresentation: AnalyticsLoadedSnapshot?

    var body: some View {
        let evaluation = range.evaluation(referenceDate: referenceDate, liveNow: liveNow)
        let presentation = AnalyticsSnapshotPresentation(
            store: store,
            range: range,
            evaluation: evaluation,
            loaded: loadedPresentation
        )

        List {
            AnalyticsPeriodSection(
                range: $range,
                referenceDate: $referenceDate,
                liveNow: liveNow,
                monthNavigationAnchor: $monthNavigationAnchor,
                isRefreshing: presentation.phase.isRefreshing
            )
            if let displayedPresentation = presentation.displayed {
                categoryContent(
                    snapshot: displayedPresentation.snapshot,
                    displayedRange: displayedPresentation.request.range,
                    displayedReferenceDate:
                    displayedPresentation.request.evaluationKey.interval.start,
                    isPlaceholder: presentation.phase.obscuresLoadedMetrics
                )
            } else {
                ProgressView()
                    .frame(maxWidth: .infinity, minHeight: 160)
                    .accessibilityLabel(AppStrings.localized("analytics.loading"))
                    .accessibilityIdentifier("analytics.detail.initialLoading")
            }
        }
        .task(id: presentation.request) {
            guard let loaded = await presentation.load(
                store: store,
                range: range,
                evaluation: evaluation
            ) else { return }
            loadedPresentation = loaded
        }
        .appSheetListStyle()
        .bottomScrollClearance()
        .scrollContentBackground(.hidden)
        .background(AppColors.background)
        .navigationTitle(category.destinationTitle)
        .accessibilityIdentifier("analytics.categoryDetail.\(category.rawValue)")
        .appInlineNavigationTitle()
        .transaction { transaction in
            transaction.animation = nil
        }
    }
}
