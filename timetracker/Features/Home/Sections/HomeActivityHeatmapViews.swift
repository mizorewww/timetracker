import SwiftUI

struct HomeActivityHeatmapRefreshRequest: Hashable {
    let selectedTaskIDs: [UUID]
    let period: ActivityHeatmapPeriod
    let analyticsRevision: UInt
    let taskReadModelRevision: UInt64
    let localDay: Date
    let localWeekStart: Date
    let liveRefreshBucket: Int?
    let clockRevision: UInt

    @MainActor
    init(
        store: TimeTrackerStore,
        now: Date,
        calendar: Calendar,
        clockRevision: UInt
    ) {
        selectedTaskIDs = store.todayHeatmapRenderableTaskIDs
        period = store.preferences.todayHeatmapPeriod
        analyticsRevision = store.analyticsRevision
        taskReadModelRevision = store.taskReadModelRevision
        localDay = calendar.startOfDay(for: now)
        localWeekStart = calendar.dateInterval(
            of: .weekOfYear,
            for: now
        )?.start ?? localDay
        liveRefreshBucket = store.activeSegments.isEmpty
            ? nil
            : Int(now.timeIntervalSinceReferenceDate / 60)
        self.clockRevision = clockRevision
    }
}

private struct LoadedHomeActivityHeatmaps {
    let request: HomeActivityHeatmapRefreshRequest
    let snapshots: [TaskActivityHeatmapSnapshot]
}

struct HomeActivityHeatmapSection: View {
    let store: TimeTrackerStore
    let container: HomeSectionContainer

    @Environment(\.calendar) private var calendar
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.todayClockIsActive) private var clockIsActive
    @State private var clockRevision: UInt = 0
    @State private var loadedHeatmaps: LoadedHomeActivityHeatmaps?

    var body: some View {
        Group {
            if clockIsActive {
                TimelineView(.periodic(from: .now, by: 60)) { context in
                    let request = HomeActivityHeatmapRefreshRequest(
                        store: store,
                        now: context.date,
                        calendar: calendar,
                        clockRevision: clockRevision
                    )
                    Group {
                        if request.selectedTaskIDs.isEmpty == false {
                            // Keep showing the last resolved snapshots while a newer
                            // request computes, so recomputation never collapses the
                            // section into a spinner mid-scroll.
                            section(loadedHeatmaps?.snapshots)
                        }
                    }
                    .task(id: request) {
                        guard request.selectedTaskIDs.isEmpty == false else {
                            loadedHeatmaps = nil
                            return
                        }
                        let snapshots = await store.todayTaskActivityHeatmapSnapshots(
                            period: request.period,
                            now: context.date,
                            calendar: calendar
                        )
                        guard Task<Never, Never>.isCancelled == false else { return }
                        loadedHeatmaps = LoadedHomeActivityHeatmaps(
                            request: request,
                            snapshots: snapshots
                        )
                    }
                }
            } else {
                // Static render while the Today tab is not selected.
                section(loadedHeatmaps?.snapshots)
            }
        }
        .onChange(of: scenePhase) { _, phase in
            guard phase == .active else { return }
            refreshClock()
        }
        .onReceive(
            NotificationCenter.default.publisher(
                for: .NSSystemClockDidChange
            )
        ) { _ in
            refreshClock()
        }
        .onReceive(
            NotificationCenter.default.publisher(
                for: .NSSystemTimeZoneDidChange
            )
        ) { _ in
            refreshClock()
        }
        .onReceive(
            NotificationCenter.default.publisher(
                for: .NSCalendarDayChanged
            )
        ) { _ in
            refreshClock()
        }
    }

    @ViewBuilder
    private func section(
        _ snapshots: [TaskActivityHeatmapSnapshot]?
    ) -> some View {
        if snapshots?.isEmpty != true {
            switch container {
            case .card:
                VStack(alignment: .leading, spacing: 10) {
                    HomeActivityHeatmapHeader(
                        container: .card,
                        taskCount: snapshots.map { taskCount($0.count) },
                        snapshots: snapshots ?? []
                    )
                    if let snapshots {
                        LazyVStack(spacing: 10) {
                            ForEach(snapshots) { snapshot in
                                TaskActivityHeatmapCard(snapshot: snapshot)
                                    .padding(HomeLayoutPolicy.visualizationCardPadding)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .appCard(padding: 0)
                                    .accessibilityElement(children: .contain)
                                    .accessibilityIdentifier(
                                        "home.heatmap.card.\(snapshot.taskID.uuidString)"
                                    )
                            }
                        }
                    } else {
                        loadingCard
                    }
                }
            case .listSection:
                if let snapshots {
                    ForEach(snapshots) { snapshot in
                        Section {
                            TaskActivityHeatmapCard(snapshot: snapshot)
                                .homeVisualizationListCard(
                                    accessibilityIdentifier:
                                    "home.heatmap.card.\(snapshot.taskID.uuidString)"
                                )
                        } header: {
                            if snapshot.id == snapshots.first?.id {
                                HomeActivityHeatmapHeader(
                                    container: .listSection,
                                    taskCount: taskCount(snapshots.count),
                                    snapshots: snapshots
                                )
                                .textCase(nil)
                            }
                        }
                    }
                } else {
                    Section {
                        ProgressView()
                            .frame(maxWidth: .infinity)
                            .frame(height: 104)
                            .homeVisualizationListCard(
                                accessibilityIdentifier: "home.heatmap.loadingCard"
                            )
                    } header: {
                        HomeActivityHeatmapHeader(
                            container: .listSection,
                            taskCount: nil,
                            snapshots: []
                        )
                        .textCase(nil)
                    }
                }
            }
        }
    }

    private var loadingCard: some View {
        ProgressView()
            .frame(maxWidth: .infinity)
            .frame(height: 120)
            .padding(HomeLayoutPolicy.visualizationCardPadding)
            .appCard(padding: 0)
    }

    private func taskCount(_ count: Int) -> String {
        String.localizedStringWithFormat(
            AppStrings.localized("home.heatmap.taskCount"),
            Int64(count)
        )
    }

    private func refreshClock() {
        clockRevision &+= 1
    }
}

private struct HomeActivityHeatmapHeader: View {
    let container: HomeSectionContainer
    var taskCount: String?
    var snapshots: [TaskActivityHeatmapSnapshot] = []

    @Environment(\.locale) private var locale

    var body: some View {
        HomeSectionHeader(
            container: container,
            title: AppStrings.localized("home.heatmap.title"),
            summary: taskCount,
            accessibilityIdentifier: "home.heatmaps.header"
        ) {
            HomeSectionInformationButton.heatmaps(
                snapshots: snapshots,
                locale: locale
            )
        }
    }
}
