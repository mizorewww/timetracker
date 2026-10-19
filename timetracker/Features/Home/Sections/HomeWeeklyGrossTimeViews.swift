import SwiftUI

struct HomeWeeklyGrossTimeSection: View {
    let store: TimeTrackerStore
    let container: HomeSectionContainer
    let now: Date

    @Environment(\.calendar) private var calendar
    @Environment(\.pageLiveClocksActive) private var clockIsActive
    @State private var snapshot: WeeklyGrossTimeSnapshot?

    var body: some View {
        let request = HomeWeeklyGrossTimeRefreshRequest(
            store: store,
            snapshot: snapshot,
            now: now,
            calendar: calendar
        )
        section(
            snapshot: snapshot?.interval == request.evaluationKey.interval
                ? snapshot
                : nil
        )
        // Recompute only while Today is the visible page.
        .task(id: clockIsActive ? request : nil) {
            guard clockIsActive else { return }
            snapshot = store.weeklyGrossTimeSnapshot(now: now, calendar: calendar)
        }
    }

    @ViewBuilder
    private func section(snapshot: WeeklyGrossTimeSnapshot?) -> some View {
        // A compact list-section header has no room for the two totals beside
        // the title (the title wraps and the totals truncate), so only the
        // card shows them.
        let header = HomeWeeklyGrossTimeHeader(
            container: container,
            total: container == .card ? snapshot.flatMap(Self.totalText) : nil
        )
        switch container {
        case .card:
            VStack(alignment: .leading, spacing: 10) {
                header
                chart(snapshot: snapshot, chartHeight: 210, emptyHeight: 96)
                    .padding(HomeLayoutPolicy.visualizationCardPadding)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .appCard(padding: 0)
                    .accessibilityElement(children: .contain)
                    .accessibilityIdentifier("home.weeklyGross.card")
            }
        case .listSection:
            Section {
                chart(snapshot: snapshot, chartHeight: 190, emptyHeight: 64)
                    .homeVisualizationListCard(
                        accessibilityIdentifier: "home.weeklyGross.card"
                    )
            } header: {
                header
                    .textCase(nil)
            }
        }
    }

    @ViewBuilder
    private func chart(
        snapshot: WeeklyGrossTimeSnapshot?,
        chartHeight: CGFloat,
        emptyHeight: CGFloat
    ) -> some View {
        if let snapshot {
            HomeWeeklyGrossTimeChart(
                snapshot: snapshot,
                chartHeight: chartHeight,
                emptyHeight: emptyHeight,
                calendar: calendar
            )
        } else {
            ProgressView()
                .frame(maxWidth: .infinity)
                .frame(height: chartHeight)
        }
    }

    private static func totalText(_ snapshot: WeeklyGrossTimeSnapshot) -> String? {
        guard snapshot.hasTrackedTime else { return nil }
        return String.localizedStringWithFormat(
            AppStrings.localized("home.weeklyGross.totalFormat"),
            DurationFormatter.chart(snapshot.totalGrossSeconds),
            DurationFormatter.chart(snapshot.totalWallSeconds)
        )
    }
}

private struct HomeWeeklyGrossTimeHeader: View {
    let container: HomeSectionContainer
    let total: String?

    var body: some View {
        HomeSectionHeader(
            container: container,
            title: AppStrings.localized("home.weeklyGross.title"),
            summary: total,
            accessibilityIdentifier: "home.weeklyGross.header"
        ) {
            HomeSectionInformationButton.weeklyGross
        }
    }
}
