import SwiftUI

struct DesktopMainView: View {
    let store: TimeTrackerStore

    var body: some View {
        GeometryReader { proxy in
            let layout = HomeLayoutPolicy(width: proxy.size.width)
            ScrollView {
                VStack(alignment: .leading, spacing: layout.contentSpacing) {
                    HeaderBar()
                    MetricsAndActions(store: store, horizontal: layout.usesHorizontalMetrics)
                    ActiveTimersSection(store: store)
                    QuickStartSection(store: store)
                    TaskForecastSummarySection(store: store)
                    HomeCountdownSection(store: store)
                    TimelineSection(store: store)
                }
                .padding(layout.pagePadding)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .background(AppColors.background)
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
