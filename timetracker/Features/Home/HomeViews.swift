import SwiftUI

struct DesktopMainView: View {
    let store: TimeTrackerStore
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
                openTask: openTask
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

    var body: some View {
        VStack(alignment: .leading, spacing: layout.contentSpacing) {
            Text(.app("home.subtitle"))
                .font(.subheadline)
                .foregroundStyle(.secondary)
            ActiveTimersSection(
                store: store,
                segments: content.activeSegments,
                openTask: openTask
            )
            TodayOverviewSection(store: store)

            if layout.usesTwoColumnContent && content.hasSupportingContent {
                HStack(alignment: .top, spacing: layout.contentSpacing) {
                    primarySections
                        .frame(maxWidth: .infinity, alignment: .topLeading)
                    supportingSections
                        .frame(width: layout.supportingColumnWidth, alignment: .topLeading)
                }
            } else {
                primarySections
                supportingSections
            }
        }
    }

    private var primarySections: some View {
        VStack(alignment: .leading, spacing: layout.contentSpacing) {
            QuickStartSection(
                store: store,
                tasks: content.quickStartTasks,
                openTask: openTask
            )
            TimelineSection(
                store: store,
                segments: content.timelineSegments,
                openTask: openTask
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
