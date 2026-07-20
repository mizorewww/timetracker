import SwiftUI

struct HomeActivityHeatmapRefreshRequest: Hashable {
    let selectedTaskIDs: [UUID]
    let analyticsRevision: UInt
    let taskReadModelRevision: UInt64
    let localDay: Date
    let localWeekStart: Date
    let clockRevision: UInt

    @MainActor
    init(
        store: TimeTrackerStore,
        now: Date,
        calendar: Calendar,
        clockRevision: UInt
    ) {
        selectedTaskIDs = store.preferences.todayHeatmapTaskIDs
        analyticsRevision = store.analyticsRevision
        taskReadModelRevision = store.taskReadModelRevision
        localDay = calendar.startOfDay(for: now)
        localWeekStart = calendar.dateInterval(
            of: .weekOfYear,
            for: now
        )?.start ?? localDay
        self.clockRevision = clockRevision
    }
}

private struct LoadedHomeActivityHeatmap {
    let request: HomeActivityHeatmapRefreshRequest
    let snapshot: ActivityHeatmapSnapshot
}

struct HomeActivityHeatmapSection: View {
    let store: TimeTrackerStore
    let container: HomeSectionContainer

    @Environment(\.calendar) private var calendar
    @Environment(\.scenePhase) private var scenePhase
    @State private var clockRevision: UInt = 0
    @State private var loadedSnapshot: LoadedHomeActivityHeatmap?

    var body: some View {
        let request = HomeActivityHeatmapRefreshRequest(
            store: store,
            now: Date(),
            calendar: calendar,
            clockRevision: clockRevision
        )
        Group {
            if request.selectedTaskIDs.isEmpty == false {
                if let loadedSnapshot,
                   loadedSnapshot.request == request {
                    section(loadedSnapshot.snapshot)
                } else {
                    loadingSection
                }
            }
        }
        .task(id: request) {
            guard request.selectedTaskIDs.isEmpty == false else {
                loadedSnapshot = nil
                return
            }
            let snapshot = store.todayActivityHeatmapSnapshot(
                now: Date(),
                calendar: calendar
            )
            guard Task<Never, Never>.isCancelled == false else { return }
            loadedSnapshot = LoadedHomeActivityHeatmap(
                request: request,
                snapshot: snapshot
            )
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
    private var loadingSection: some View {
        switch container {
        case .card:
            VStack(alignment: .leading, spacing: 10) {
                SectionTitle(
                    title: AppStrings.localized("heatmap.settings.title")
                )
                ProgressView()
                    .frame(maxWidth: .infinity)
                    .frame(height: 120)
                    .padding(16)
                    .appCard(padding: 0)
            }
        case .listSection:
            Section {
                ProgressView()
                    .frame(maxWidth: .infinity)
                    .frame(height: 104)
                    .padding(.vertical, 6)
            } header: {
                Text(.app("heatmap.settings.title"))
                    .textCase(nil)
            }
        }
    }

    @ViewBuilder
    private func section(_ snapshot: ActivityHeatmapSnapshot) -> some View {
        switch container {
        case .card:
            VStack(alignment: .leading, spacing: 10) {
                SectionTitle(
                    title: AppStrings.localized("heatmap.settings.title"),
                    trailing: completionCount(snapshot),
                    trailingTint: .secondary
                )
                VStack(alignment: .leading, spacing: 8) {
                    heatmap(snapshot)
                    Text(.app("home.heatmap.footer"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                    .padding(16)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .appCard(padding: 0)
                    .accessibilityElement(children: .contain)
                    .accessibilityIdentifier("home.heatmap")
            }
        case .listSection:
            Section {
                heatmap(snapshot)
                    .padding(.vertical, 6)
                    .accessibilityElement(children: .contain)
                    .accessibilityIdentifier("home.heatmap")
            } header: {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(.app("heatmap.settings.title"))
                    Spacer(minLength: 8)
                    Text(completionCount(snapshot))
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
                .textCase(nil)
                .accessibilityElement(children: .combine)
                .accessibilityAddTraits(.isHeader)
            } footer: {
                Text(.app("home.heatmap.footer"))
            }
        }
    }

    private func heatmap(
        _ snapshot: ActivityHeatmapSnapshot
    ) -> some View {
        ActivityHeatmapGrid(
            snapshot: snapshot,
            accessibilityTitle: AppStrings.localized("heatmap.settings.title"),
            accessibilitySummary: String.localizedStringWithFormat(
                AppStrings.localized("home.heatmap.accessibilitySummary"),
                snapshot.totalCompletionCount,
                snapshot.activeDayCount
            )
        )
        .accessibilityIdentifier("home.heatmap.grid")
    }

    private func completionCount(
        _ snapshot: ActivityHeatmapSnapshot
    ) -> String {
        String.localizedStringWithFormat(
            AppStrings.localized("home.heatmap.completionCount"),
            snapshot.totalCompletionCount
        )
    }

    private func refreshClock() {
        clockRevision &+= 1
    }
}
