import SwiftUI

struct AnalyticsContent: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    let snapshot: AnalyticsSnapshot
    @Binding var range: AnalyticsRange
    @Binding var referenceDate: Date
    let liveNow: Date
    @Binding var monthNavigationAnchor: AnalyticsMonthNavigationAnchor?
    let isRefreshing: Bool

    var body: some View {
        List {
            AnalyticsPeriodSection(
                range: $range,
                referenceDate: $referenceDate,
                liveNow: liveNow,
                monthNavigationAnchor: $monthNavigationAnchor,
                isRefreshing: isRefreshing
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
                AnalyticsHomeSectionHeader(
                    title: AppStrings.localized("analytics.review.title"),
                    subtitle: AppStrings.localized("analytics.review.subtitle"),
                    identifier: "analytics.section.review"
                )
            }

            Section {
                categoryLinks(AnalyticsCategory.exploreCategories)
            } header: {
                AnalyticsHomeSectionHeader(
                    title: AppStrings.localized("analytics.categories.title"),
                    subtitle: AppStrings.localized("analytics.categories.subtitle"),
                    identifier: "analytics.section.explore"
                )
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

private struct AnalyticsHomeSectionHeader: View {
    let title: String
    let subtitle: String
    let identifier: String

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
            Text(subtitle)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .textCase(nil)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
        .accessibilityIdentifier(identifier)
    }
}
