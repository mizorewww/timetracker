import SwiftUI

struct AnalyticsContent: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    let store: TimeTrackerStore
    /// `nil` only during the first uncached load. Later period changes keep
    /// the last section shells mounted with redacted, non-interactive content.
    let snapshot: AnalyticsSnapshot?
    let contentIsPlaceholder: Bool
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

            if let snapshot {
                dataSections(snapshot: snapshot)
            } else {
                ProgressView()
                    .frame(maxWidth: .infinity, minHeight: 240)
                    .accessibilityLabel(AppStrings.localized("analytics.loading"))
                    .accessibilityIdentifier("analytics.initialLoading")
            }

            // The tracked-task heatmaps have their own data chain and period,
            // independent of the analytics range, so they stay mounted while
            // a newly selected period loads.
            HomeActivityHeatmapSection(
                store: store,
                container: .listSection
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
        .accessibilityIdentifier("analytics.view")
        .transaction { transaction in
            transaction.animation = nil
        }
    }

    @ViewBuilder
    private func dataSections(snapshot: AnalyticsSnapshot) -> some View {
        Section {
            AnalyticsHomeSummaryRow(snapshot: snapshot)
                .analyticsLoadingPlaceholder(contentIsPlaceholder)
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
            categoryLinks(AnalyticsCategory.reviewCategories, snapshot: snapshot)
        } header: {
            AnalyticsHomeSectionHeader(
                title: AppStrings.localized("analytics.review.title"),
                subtitle: AppStrings.localized("analytics.review.subtitle"),
                identifier: "analytics.section.review"
            )
        }

        Section {
            categoryLinks(AnalyticsCategory.exploreCategories, snapshot: snapshot)
        } header: {
            AnalyticsHomeSectionHeader(
                title: AppStrings.localized("analytics.categories.title"),
                subtitle: AppStrings.localized("analytics.categories.subtitle"),
                identifier: "analytics.section.explore"
            )
        }
    }

    private func categoryLinks(
        _ categories: [AnalyticsCategory],
        snapshot: AnalyticsSnapshot
    ) -> some View {
        ForEach(categories) { category in
            NavigationLink(value: category) {
                AnalyticsCategoryRow(category: category, snapshot: snapshot)
            }
            .accessibilityIdentifier("analytics.category.\(category.rawValue)")
            .analyticsLoadingPlaceholder(contentIsPlaceholder)
        }
    }
}

extension View {
    @ViewBuilder
    func analyticsLoadingPlaceholder(_ isActive: Bool) -> some View {
        if isActive {
            redacted(reason: .placeholder)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        } else {
            self
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
