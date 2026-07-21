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

private struct LoadedHomeActivityHeatmaps {
    let request: HomeActivityHeatmapRefreshRequest
    let snapshots: [TaskActivityHeatmapSnapshot]
}

struct HomeActivityHeatmapSection: View {
    let store: TimeTrackerStore
    let container: HomeSectionContainer

    @Environment(\.calendar) private var calendar
    @Environment(\.scenePhase) private var scenePhase
    @State private var clockRevision: UInt = 0
    @State private var loadedHeatmaps: LoadedHomeActivityHeatmaps?

    var body: some View {
        let request = HomeActivityHeatmapRefreshRequest(
            store: store,
            now: Date(),
            calendar: calendar,
            clockRevision: clockRevision
        )
        Group {
            if request.selectedTaskIDs.isEmpty == false {
                if let loadedHeatmaps,
                   loadedHeatmaps.request == request {
                    section(loadedHeatmaps.snapshots)
                } else {
                    loadingSection
                }
            }
        }
        .task(id: request) {
            guard request.selectedTaskIDs.isEmpty == false else {
                loadedHeatmaps = nil
                return
            }
            let snapshots = store.todayTaskActivityHeatmapSnapshots(
                now: Date(),
                calendar: calendar
            )
            guard Task<Never, Never>.isCancelled == false else { return }
            loadedHeatmaps = LoadedHomeActivityHeatmaps(
                request: request,
                snapshots: snapshots
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
                SectionTitle(title: AppStrings.localized("home.heatmap.title"))
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
                Text(.app("home.heatmap.title"))
                    .textCase(nil)
            }
        }
    }

    @ViewBuilder
    private func section(
        _ snapshots: [TaskActivityHeatmapSnapshot]
    ) -> some View {
        if snapshots.isEmpty == false {
            switch container {
            case .card:
                VStack(alignment: .leading, spacing: 10) {
                    SectionTitle(
                        title: AppStrings.localized("home.heatmap.title"),
                        trailing: taskCount(snapshots.count),
                        trailingTint: .secondary
                    )
                    LazyVStack(spacing: 10) {
                        ForEach(snapshots) { snapshot in
                            TaskActivityHeatmapCard(snapshot: snapshot)
                                .padding(16)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .appCard(padding: 0)
                        }
                    }
                }
                .accessibilityIdentifier("home.heatmaps")
            case .listSection:
                Section {
                    ForEach(snapshots) { snapshot in
                        TaskActivityHeatmapCard(snapshot: snapshot)
                            .padding(.vertical, 6)
                    }
                } header: {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(.app("home.heatmap.title"))
                        Spacer(minLength: 8)
                        Text(taskCount(snapshots.count))
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                    .textCase(nil)
                    .accessibilityElement(children: .combine)
                    .accessibilityAddTraits(.isHeader)
                } footer: {
                    Text(.app("home.heatmap.section.footer"))
                }
                .accessibilityIdentifier("home.heatmaps")
            }
        }
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

private struct TaskActivityHeatmapCard: View {
    let snapshot: TaskActivityHeatmapSnapshot

    @Environment(\.locale) private var locale

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header
            ActivityHeatmapGrid(
                snapshot: snapshot,
                accessibilitySummary: accessibilitySummary
            )
            .accessibilityIdentifier(
                "home.heatmap.grid.\(snapshot.taskID.uuidString)"
            )
            Text(snapshot.hasActivity ? metricExplanation : noActivityExplanation)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(
            "home.heatmap.\(snapshot.taskID.uuidString)"
        )
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 10) {
            TaskIcon(
                visual: TaskVisualPresentation(
                    iconName: snapshot.iconName,
                    colorHex: snapshot.colorHex
                ),
                size: 30
            )
            VStack(alignment: .leading, spacing: 2) {
                Text(snapshot.title)
                    .font(.headline)
                    .foregroundStyle(.primary)
                    .lineLimit(2)
                Text(metricTitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Text(headerValue)
                .font(.subheadline.weight(.semibold).monospacedDigit())
                .foregroundStyle(Color(hex: snapshot.colorHex) ?? .blue)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .allowsTightening(true)
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }

    private var metricTitle: String {
        switch snapshot.metric {
        case .trackedDuration:
            AppStrings.localized("home.heatmap.metric.duration")
        case .checklistCompletions:
            AppStrings.localized("home.heatmap.metric.checklist")
        case let .quantity(unitLabel):
            String.localizedStringWithFormat(
                AppStrings.localized("home.heatmap.metric.quantityFormat"),
                unitLabel
            )
        }
    }

    private var totalValue: String {
        ActivityHeatmapValueFormatter.compact(
            snapshot.totalValue,
            metric: snapshot.metric,
            locale: locale
        )
    }

    private var headerValue: String {
        switch snapshot.metric {
        case .quantity:
            snapshot.totalValue.formatted(.number.locale(locale))
        case .trackedDuration, .checklistCompletions:
            totalValue
        }
    }

    private var maximumDailyValue: String {
        ActivityHeatmapValueFormatter.compact(
            snapshot.maximumDailyValue,
            metric: snapshot.metric,
            locale: locale
        )
    }

    private var metricExplanation: String {
        switch snapshot.metric {
        case .trackedDuration:
            String.localizedStringWithFormat(
                AppStrings.localized("home.heatmap.footer.durationFormat"),
                maximumDailyValue
            )
        case .checklistCompletions:
            String.localizedStringWithFormat(
                AppStrings.localized("home.heatmap.footer.checklistFormat"),
                maximumDailyValue
            )
        case .quantity:
            String.localizedStringWithFormat(
                AppStrings.localized("home.heatmap.footer.quantityFormat"),
                maximumDailyValue
            )
        }
    }

    private var noActivityExplanation: String {
        String.localizedStringWithFormat(
            AppStrings.localized("home.heatmap.footer.noActivityFormat"),
            metricTitle
        )
    }

    private var accessibilitySummary: String {
        String.localizedStringWithFormat(
            AppStrings.localized("home.heatmap.accessibilitySummaryFormat"),
            metricTitle,
            totalValue,
            Int64(snapshot.activeDayCount),
            maximumDailyValue
        )
    }
}
