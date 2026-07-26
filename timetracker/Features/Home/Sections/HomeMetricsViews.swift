import SwiftUI

struct TodayOverviewSection: View {
    let store: TimeTrackerStore

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HomeOverviewHeader(
                container: .card,
                showsWallTime: store.preferences.showGrossAndWallTogether
            )
            CompactTodaySummaryRow(store: store)
                .padding(14)
                .frame(maxWidth: .infinity)
                .appCard(padding: 0)
                .accessibilityIdentifier("home.overview")
        }
    }
}

struct HomeOverviewHeader: View {
    let container: HomeSectionContainer
    let showsWallTime: Bool

    var body: some View {
        HomeSectionHeader(
            container: container,
            title: AppStrings.localized("home.overview.title"),
            accessibilityIdentifier: "home.overview.header"
        ) {
            HomeSectionInformationButton.overview(
                showsWallTime: showsWallTime
            )
        }
    }
}
