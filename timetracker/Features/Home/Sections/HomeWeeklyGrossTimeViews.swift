import SwiftUI

struct HomeWeeklyGrossTimeSection: View {
    let store: TimeTrackerStore
    let container: HomeSectionContainer

    @Environment(\.calendar) private var calendar
    @Environment(\.scenePhase) private var scenePhase
    @State private var snapshot: WeeklyGrossTimeSnapshot?
    @State private var clockRevision: UInt = 0

    var body: some View {
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
                    total: snapshot.flatMap { snapshot in
                        snapshot.hasTrackedTime
                            ? DurationFormatter.chart(snapshot.totalGrossSeconds)
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
                            .frame(height: 238)
                    }
                }
                    .padding(16)
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
                            chartHeight: 170,
                            emptyHeight: 64,
                            calendar: calendar
                        )
                    } else {
                        ProgressView()
                            .frame(maxWidth: .infinity)
                            .frame(height: 170)
                    }
                }
                    .padding(.vertical, 6)
                    .accessibilityElement(children: .contain)
                    .accessibilityIdentifier("home.weeklyGross.card")
            } header: {
                HomeWeeklyGrossTimeHeader(
                    container: .listSection,
                    total: snapshot.flatMap { snapshot in
                        snapshot.hasTrackedTime
                            ? DurationFormatter.chart(snapshot.totalGrossSeconds)
                            : nil
                    }
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
        HStack(alignment: .center, spacing: 4) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                title
                Spacer(minLength: 8)
                if let total {
                    Text(total)
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isHeader)

            HomeSectionInformationButton.weeklyGross
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("home.weeklyGross.header")
    }

    @ViewBuilder
    private var title: some View {
        switch container {
        case .card:
            Text(.app("home.weeklyGross.title"))
                .font(.headline)
        case .listSection:
            Text(.app("home.weeklyGross.title"))
        }
    }
}
