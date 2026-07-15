import SwiftUI

struct DesktopMainView: View {
    let store: TimeTrackerStore

    var body: some View {
        GeometryReader { proxy in
            let layout = HomeLayoutPolicy(width: proxy.size.width)
            let content = TodayHomeContent(store: store, quickStartLimit: 6)
            ScrollView {
                DesktopTodayContent(store: store, content: content, layout: layout)
                    .frame(width: layout.contentWidth, alignment: .leading)
                    .padding(.vertical, layout.pagePadding)
                    .frame(maxWidth: .infinity, alignment: .center)
            }
            .background(AppColors.background)
            .accessibilityIdentifier("home.view")
        }
    }
}

private struct DesktopTodayContent: View {
    let store: TimeTrackerStore
    let content: TodayHomeContent
    let layout: HomeLayoutPolicy

    var body: some View {
        VStack(alignment: .leading, spacing: layout.contentSpacing) {
            HeaderBar()
            ActiveTimersSection(store: store, segments: content.activeSegments)
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
            QuickStartSection(store: store, tasks: content.quickStartTasks)
            TimelineSection(store: store, segments: content.timelineSegments)
        }
    }

    private var supportingSections: some View {
        VStack(alignment: .leading, spacing: layout.contentSpacing) {
            TaskForecastSummarySection(store: store, forecasts: content.forecasts)
            HomeCountdownSection(events: content.countdownEvents)
        }
    }
}

struct HeaderBar: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(AppStrings.today)
                .font(.largeTitle.bold())
            Text(.app("home.subtitle"))
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }
}
