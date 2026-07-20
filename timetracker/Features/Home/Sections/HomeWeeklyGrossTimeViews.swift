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
                if let snapshot,
                   snapshot.interval == request.evaluationKey.interval {
                    section(snapshot: snapshot)
                } else {
                    loadingSection
                }
            }
            .task(id: request) {
                snapshot = store.weeklyGrossTimeSnapshot(
                    now: context.date,
                    calendar: calendar
                )
            }
        }
        .accessibilityIdentifier("home.weeklyGross")
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
    private var loadingSection: some View {
        switch container {
        case .card:
            VStack(alignment: .leading, spacing: 10) {
                SectionTitle(
                    title: AppStrings.localized("home.weeklyGross.title")
                )
                ProgressView()
                    .frame(maxWidth: .infinity)
                    .frame(height: 238)
                    .padding(16)
                    .appCard(padding: 0)
            }
        case .listSection:
            Section {
                ProgressView()
                    .frame(maxWidth: .infinity)
                    .frame(height: 170)
                    .padding(.vertical, 6)
            } header: {
                Text(.app("home.weeklyGross.title"))
                    .textCase(nil)
            }
        }
    }

    @ViewBuilder
    private func section(snapshot: WeeklyGrossTimeSnapshot) -> some View {
        switch container {
        case .card:
            VStack(alignment: .leading, spacing: 10) {
                cardHeader(snapshot: snapshot)
                VStack(alignment: .leading, spacing: 8) {
                    HomeWeeklyGrossTimeChart(
                        snapshot: snapshot,
                        chartHeight: 210,
                        emptyHeight: 96,
                        calendar: calendar
                    )
                    if snapshot.hasTrackedTime {
                        Text(.app("home.weeklyGross.footer"))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                    .padding(16)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .appCard(padding: 0)
            }
        case .listSection:
            Section {
                HomeWeeklyGrossTimeChart(
                    snapshot: snapshot,
                    chartHeight: 170,
                    emptyHeight: 64,
                    calendar: calendar
                )
                    .padding(.vertical, 6)
            } header: {
                listHeader(snapshot: snapshot)
                    .textCase(nil)
            } footer: {
                if snapshot.hasTrackedTime {
                    Text(.app("home.weeklyGross.footer"))
                }
            }
        }
    }

    private func cardHeader(
        snapshot: WeeklyGrossTimeSnapshot
    ) -> some View {
        SectionTitle(
            title: AppStrings.localized("home.weeklyGross.title"),
            trailing: snapshot.hasTrackedTime
                ? DurationFormatter.chart(snapshot.totalGrossSeconds)
                : nil,
            trailingTint: .secondary
        )
    }

    private func listHeader(
        snapshot: WeeklyGrossTimeSnapshot
    ) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(.app("home.weeklyGross.title"))
            Spacer(minLength: 8)
            if snapshot.hasTrackedTime {
                Text(DurationFormatter.chart(snapshot.totalGrossSeconds))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }

}
