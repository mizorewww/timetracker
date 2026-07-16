import SwiftUI

struct AnalyticsContent: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    let snapshot: AnalyticsSnapshot
    @Binding var range: AnalyticsRange
    @Binding var referenceDate: Date
    let liveNow: Date
    @Binding var monthNavigationAnchor: AnalyticsMonthNavigationAnchor?

    var body: some View {
        List {
            AnalyticsPeriodSection(
                range: $range,
                referenceDate: $referenceDate,
                liveNow: liveNow,
                monthNavigationAnchor: $monthNavigationAnchor
            )

            Section {
                AnalyticsHomeSummaryRow(snapshot: snapshot)
            } header: {
                Text(AppStrings.localized("analytics.summary.title"))
            } footer: {
                Text(
                    String(
                        format: AppStrings.localized("analytics.summary.periodFootnote"),
                        AnalyticsPeriodText.title(
                            for: range,
                            date: referenceDate,
                            liveNow: liveNow
                        )
                    )
                )
            }

            Section {
                categoryLinks(AnalyticsCategory.reviewCategories)
            } header: {
                Text(AppStrings.localized("analytics.review.title"))
            }

            Section {
                categoryLinks(AnalyticsCategory.exploreCategories)
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

    @ViewBuilder
    private func categoryLinks(_ categories: [AnalyticsCategory]) -> some View {
        ForEach(categories) { category in
            NavigationLink(value: category) {
                AnalyticsCategoryRow(category: category, snapshot: snapshot)
            }
            .accessibilityIdentifier("analytics.category.\(category.rawValue)")
        }
    }
}
