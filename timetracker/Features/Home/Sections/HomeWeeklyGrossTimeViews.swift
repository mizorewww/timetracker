import SwiftUI

struct HomeWeeklyGrossTimeSection: View {
    let store: TimeTrackerStore
    let container: HomeSectionContainer

    @Environment(\.calendar) private var calendar
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.todayClockIsActive) private var clockIsActive
    @State private var snapshot: WeeklyGrossTimeSnapshot?
    @State private var clockRevision: UInt = 0

    var body: some View {
        Group {
            if clockIsActive {
                TimelineView(.periodic(from: .now, by: 60)) { context in
                    let request = HomeWeeklyGrossTimeRefreshRequest(
                        store: store,
                        snapshot: snapshot,
                        now: context.date,
                        clockRevision: clockRevision,
                        calendar: calendar
                    )
                    Group {
                        section(
                            snapshot: snapshot?.interval == request.evaluationKey.interval
                                ? snapshot
                                : nil
                        )
                    }
                    .task(id: request) {
                        snapshot = store.weeklyGrossTimeSnapshot(
                            now: context.date,
                            calendar: calendar
                        )
                    }
                }
            } else {
                // Static render while the Today tab is not selected.
                section(snapshot: snapshot)
            }
        }
        .onChange(of: scenePhase) { _, phase in
            guard phase == .active else { return }
            clockRevision &+= 1
        }
        .onReceive(
            NotificationCenter.default.publisher(
                for: .NSSystemClockDidChange
            )
        ) { _ in
            clockRevision &+= 1
        }
        .onReceive(
            NotificationCenter.default.publisher(
                for: .NSSystemTimeZoneDidChange
            )
        ) { _ in
            clockRevision &+= 1
        }
        .onReceive(
            NotificationCenter.default.publisher(
                for: .NSCalendarDayChanged
            )
        ) { _ in
            clockRevision &+= 1
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
