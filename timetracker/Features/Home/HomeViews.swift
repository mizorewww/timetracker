import SwiftUI

struct DesktopMainView: View {
    let store: TimeTrackerStore
    @Environment(AppPresentationRouter.self) private var presentationRouter
    @State private var viewportWidth: CGFloat = 720
    @State private var todayTaskRoute: TasksRoute?

    var body: some View {
        let layout = HomeLayoutPolicy(width: viewportWidth)
        let content = TodayHomeContent(store: store, quickStartLimit: 6)

        ScrollView {
            DesktopTodayContent(
                store: store,
                content: content,
                layout: layout,
                openTask: openTask,
                startTimer: { presentationRouter.presentStartTaskPicker() }
            )
            .frame(width: layout.contentWidth, alignment: .leading)
            .padding(.vertical, layout.pagePadding)
            .frame(maxWidth: .infinity, alignment: .center)
        }
        .onGeometryChange(for: CGFloat.self) { proxy in
            proxy.size.width
        } action: { width in
            guard abs(viewportWidth - width) > 0.5 else { return }
            viewportWidth = width
        }
        .background(AppColors.background)
        .accessibilityIdentifier("home.view")
        .navigationTitle(AppStrings.today)
        .todayTaskNavigationDestination(
            store: store,
            route: $todayTaskRoute
        )
        #if os(iOS)
        .navigationBarTitleDisplayMode(.large)
        #endif
    }

    private func openTask(_ taskID: UUID) {
        todayTaskRoute = store.prepareTaskDetailRoute(taskID)
    }
}

private struct DesktopTodayContent: View {
    let store: TimeTrackerStore
    let content: TodayHomeContent
    let layout: HomeLayoutPolicy
    let openTask: (UUID) -> Void
    let startTimer: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: layout.contentSpacing) {
            DesktopTodayCurrentStateSections(
                store: store,
                segments: content.activeSegments,
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
            segments: content.timelineSegments,
            openTask: openTask
        )
    }

    private var visualizationSections: some View {
        VStack(alignment: .leading, spacing: layout.contentSpacing) {
            HomeWeeklyGrossTimeSection(
                store: store,
                container: .card
            )
            HomeActivityHeatmapSection(
                store: store,
                container: .card
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
                overview
                    .frame(
                        width: layout.currentStateOverviewColumnWidth,
                        alignment: .topLeading
                    )
            }
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
        TodayOverviewSection(store: store)
    }
}
