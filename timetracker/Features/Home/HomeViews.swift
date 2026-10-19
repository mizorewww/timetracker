import SwiftUI

struct DesktopMainView: View {
    let store: TimeTrackerStore
    @Environment(AppPresentationRouter.self) private var presentationRouter
    @State private var viewportMeasurement = HomeViewportMeasurement(width: 720)
    @State private var clockNow = Date()

    var body: some View {
        let layout = HomeLayoutPolicy(width: viewportMeasurement.layoutWidth)
        // A ledger write can re-render the page between clock ticks; never
        // read a just-written stop date as a still-open future end.
        let now = max(clockNow, Date())
        let today = store.todaySnapshot(now: now, quickStartLimit: 6)

        ScrollView {
            DesktopTodayContent(
                store: store,
                today: today,
                now: now,
                layout: layout,
                openTask: openTask,
                startTimer: { presentationRouter.present(.startTaskPicker) }
            )
            .frame(width: layout.contentWidth, alignment: .leading)
            .padding(.vertical, layout.pagePadding)
            .frame(maxWidth: .infinity, alignment: .center)
        }
        .onGeometryChange(for: HomeViewportMeasurement.self) { proxy in
            HomeViewportMeasurement(width: proxy.size.width)
        } action: { measurement in
            viewportMeasurement = measurement
        }
        .background(AppColors.background)
        .accessibilityIdentifier("home.view")
        .liveClock($clockNow, until: LiveClockDeadline.next(after: now, isLive: today.live.isLive))
        .navigationTitle(AppStrings.today)
        .todayTaskNavigationDestination(
            store: store,
            route: todayTaskRoute
        )
        #if os(iOS)
        .navigationBarTitleDisplayMode(.large)
        #endif
    }

    private func openTask(_ taskID: UUID) {
        store.openTodayTaskDetail(taskID)
    }

    private var todayTaskRoute: Binding<TasksRoute?> {
        Binding(
            get: { store.todayTaskRoute },
            set: { store.todayTaskRoute = $0 }
        )
    }
}

private struct DesktopTodayContent: View {
    let store: TimeTrackerStore
    let today: TodaySnapshot
    let now: Date
    let layout: HomeLayoutPolicy
    let openTask: (UUID) -> Void
    let startTimer: () -> Void

    private var content: TodayHomeContent {
        today.content
    }

    var body: some View {
        VStack(alignment: .leading, spacing: layout.contentSpacing) {
            DesktopTodayCurrentStateSections(
                store: store,
                segments: content.activeSegments,
                metrics: today.live.metrics,
                layout: layout,
                openTask: openTask,
                startTimer: startTimer
            )
            visualizationAndQuickStart

            if layout.usesTwoColumnContent, content.hasSupportingContent {
                HStack(alignment: .top, spacing: layout.contentSpacing) {
                    timelineSection
                        .frame(maxWidth: .infinity, alignment: .topLeading)
                    supportingSections
                        .frame(width: layout.supportingColumnWidth, alignment: .topLeading)
                }
            } else {
                timelineSection
                supportingSections
            }
        }
    }

    @ViewBuilder
    private var visualizationAndQuickStart: some View {
        if layout.usesTwoColumnContent {
            HStack(alignment: .top, spacing: layout.contentSpacing) {
                visualizationSections
                    .frame(
                        width: layout.wideVisualizationColumnWidth,
                        alignment: .topLeading
                    )
                quickStartSection
                    .frame(
                        width: layout.wideQuickStartColumnWidth,
                        alignment: .topLeading
                    )
            }
        } else {
            visualizationSections
                .frame(
                    maxWidth: layout.visualizationSectionWidth,
                    alignment: .leading
                )
            quickStartSection
        }
    }

    private var quickStartSection: some View {
        QuickStartSection(
            store: store,
            tasks: content.quickStartTasks,
            openTask: openTask
        )
    }

    private var timelineSection: some View {
        TimelineSection(
            store: store,
            live: today.live,
            openTask: openTask
        )
    }

    private var visualizationSections: some View {
        VStack(alignment: .leading, spacing: layout.contentSpacing) {
            HomeWeeklyGrossTimeSection(
                store: store,
                container: .card,
                now: now
            )
            HomeActivityHeatmapSection(
                store: store,
                container: .card,
                now: now
            )
        }
    }

    private var supportingSections: some View {
        VStack(alignment: .leading, spacing: layout.contentSpacing) {
            TaskForecastSummarySection(
                store: store,
                forecasts: content.forecasts,
                openTask: openTask
            )
            HomeCountdownSection(events: content.countdownEvents)
        }
    }
}

private struct DesktopTodayCurrentStateSections: View {
    let store: TimeTrackerStore
    let segments: [TimeSegment]
    let metrics: TodayMetricsSnapshot
    let layout: HomeLayoutPolicy
    let openTask: (UUID) -> Void
    let startTimer: () -> Void

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        if layout.usesSideBySideCurrentState(
            prefersSingleColumn: dynamicTypeSize.isAccessibilitySize
        ) {
            HStack(alignment: .top, spacing: layout.contentSpacing) {
                activeTimers
                    .frame(
                        width: layout.currentStatePrimaryColumnWidth,
                        alignment: .topLeading
                    )
                    .frame(maxHeight: .infinity, alignment: .topLeading)
                overview
                    .frame(
                        width: layout.currentStateOverviewColumnWidth,
                        alignment: .topLeading
                    )
                    .frame(maxHeight: .infinity, alignment: .topLeading)
            }
            .fixedSize(horizontal: false, vertical: true)
        } else {
            VStack(alignment: .leading, spacing: layout.contentSpacing) {
                activeTimers
                overview
            }
        }
    }

    private var activeTimers: some View {
        ActiveTimersSection(
            store: store,
            segments: segments,
            openTask: openTask,
            startTimer: startTimer
        )
    }

    private var overview: some View {
        TodayOverviewSection(store: store, metrics: metrics)
    }
}
