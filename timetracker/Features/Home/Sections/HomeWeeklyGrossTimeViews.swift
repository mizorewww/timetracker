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
        switch container {
        case .card:
            VStack(alignment: .leading, spacing: 10) {
                HomeWeeklyGrossTimeHeader(
                    container: .card,
                    total: snapshot.flatMap { snapshot -> String? in
                        snapshot.hasTrackedTime
                            ? String.localizedStringWithFormat(
                                AppStrings.localized(
                                    "home.weeklyGross.totalFormat"
                                ),
                                DurationFormatter.chart(
                                    snapshot.totalGrossSeconds
                                ),
                                DurationFormatter.chart(
                                    snapshot.totalWallSeconds
                                )
                            )
                            : nil
                    }
                )
                Group {
                    if let snapshot {
                        HomeWeeklyGrossTimeChart(
                            snapshot: snapshot,
                            chartHeight: 210,
                            emptyHeight: 96,
                            calendar: calendar
                        )
                    } else {
                        ProgressView()
                            .frame(maxWidth: .infinity)
                            .frame(height: 210)
                    }
                }
                .padding(HomeLayoutPolicy.visualizationCardPadding)
                .frame(maxWidth: .infinity, alignment: .leading)
                .appCard(padding: 0)
                .accessibilityElement(children: .contain)
                .accessibilityIdentifier("home.weeklyGross.card")
            }
        case .listSection:
            Section {
                Group {
                    if let snapshot {
                        HomeWeeklyGrossTimeChart(
                            snapshot: snapshot,
                            chartHeight: 190,
                            emptyHeight: 64,
                            calendar: calendar
                        )
                    } else {
                        ProgressView()
                            .frame(maxWidth: .infinity)
                            .frame(height: 190)
                    }
                }
                .homeVisualizationListCard(
                    accessibilityIdentifier: "home.weeklyGross.card"
                )
            } header: {
                HomeWeeklyGrossTimeHeader(
                    container: .listSection,
                    total: nil
                )
                .textCase(nil)
            }
        }
    }
}

private struct HomeWeeklyGrossTimeHeader: View {
    let container: HomeSectionContainer
    var total: String?

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
