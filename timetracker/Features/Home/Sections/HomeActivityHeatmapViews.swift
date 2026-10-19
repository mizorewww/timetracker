import SwiftUI

struct HomeActivityHeatmapRefreshRequest: Hashable {
    let selectedTaskIDs: [UUID]
    let period: ActivityHeatmapPeriod
    let analyticsRevision: UInt
    let taskReadModelRevision: UInt64
    let localDay: Date
    let localWeekStart: Date
    let liveRefreshBucket: Int?

    @MainActor
    init(
        store: TimeTrackerStore,
        now: Date,
        calendar: Calendar
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
    }
}

private struct LoadedHomeActivityHeatmaps {
    let request: HomeActivityHeatmapRefreshRequest
    let snapshots: [TaskActivityHeatmapSnapshot]
}

struct HomeActivityHeatmapSection: View {
    let store: TimeTrackerStore
    let container: HomeSectionContainer
    let now: Date

    @Environment(\.calendar) private var calendar
    @Environment(\.pageLiveClocksActive) private var clockIsActive
    @State private var loadedHeatmaps: LoadedHomeActivityHeatmaps?

    var body: some View {
        let request = HomeActivityHeatmapRefreshRequest(
            store: store,
            now: now,
            calendar: calendar
        )
        Group {
            if request.selectedTaskIDs.isEmpty == false {
                // Keep showing the last resolved snapshots while a newer
                // request computes, so recomputation never collapses the
                // section into a spinner mid-scroll.
                section(loadedHeatmaps?.snapshots)
            }
        }
        // Recompute only while Today is the visible page; a background tab
        // keeps its last snapshots until it is selected again.
        .task(id: clockIsActive ? request : nil) {
            guard clockIsActive else { return }
            guard request.selectedTaskIDs.isEmpty == false else {
                loadedHeatmaps = nil
                return
            }
            let snapshots = await store.todayTaskActivityHeatmapSnapshots(
                period: request.period,
                now: now,
                calendar: calendar
            )
            guard Task<Never, Never>.isCancelled == false else { return }
            loadedHeatmaps = LoadedHomeActivityHeatmaps(
                request: request,
                snapshots: snapshots
            )
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
