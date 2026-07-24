import SwiftUI

struct TodayOverviewSection: View {
    let store: TimeTrackerStore

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HomeOverviewHeader(
                container: .card,
                showsWallTime: store.preferences.showGrossAndWallTogether
            )
            PhoneTodaySummaryRow(store: store)
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
        HStack(alignment: .center, spacing: 4) {
            title
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityElement(children: .combine)
                .accessibilityAddTraits(.isHeader)
                .accessibilityIdentifier("home.overview.header")
            HomeSectionInformationButton.overview(
                showsWallTime: showsWallTime
            )
        }
    }

    @ViewBuilder
    private var title: some View {
        switch container {
        case .card:
            Text(.app("home.overview.title"))
                .font(.headline)
        case .listSection:
            Text(.app("home.overview.title"))
        }
    }
}
