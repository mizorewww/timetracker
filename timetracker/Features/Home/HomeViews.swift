import SwiftUI
#if os(iOS)
import UIKit
#endif

struct DesktopMainView: View {
    @ObservedObject var store: TimeTrackerStore

    var body: some View {
        GeometryReader { proxy in
            let layout = HomeLayoutPolicy(width: proxy.size.width)
            ScrollView {
                VStack(alignment: .leading, spacing: layout.contentSpacing) {
                    HeaderBar(store: store, compact: layout.isCompact)
                    MetricsAndActions(store: store, horizontal: layout.usesHorizontalMetrics)
                    TimeProgressSection(store: store)
                    TaskForecastSummarySection(store: store)
                    ActiveTimersSection(store: store)
                    if layout.showsQuickStartInDesktopFlow {
                        QuickStartSection(store: store)
                    }
                    TimelineSection(store: store)
                }
                .padding(layout.pagePadding)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .background(AppColors.background)
        }
    }
}

#if os(iOS)
struct PhoneHomeView: View {
    @ObservedObject var store: TimeTrackerStore

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                MetricsAndActions(store: store, horizontal: false)
                TimeProgressSection(store: store)
                TaskForecastSummarySection(store: store)
                ActiveTimersSection(store: store)
                QuickStartSection(store: store)
                TimelineSection(store: store)
                HomeSelectedTaskSummaryCard(store: store)
            }
            .padding(.horizontal, PhoneRootChromeMetrics.pageHorizontalPadding)
            .padding(.top, 0)
            .padding(.bottom, PhoneRootChromeMetrics.scrollBottomClearance)
        }
        .phoneRootScrollBehavior()
        .phoneChromeScrollObserver(destination: .today)
        .background(AppColors.background)
        .navigationTitle(AppStrings.today)
        .navigationBarTitleDisplayMode(.large)
        .phoneRootChrome(destination: .today)
        .toolbar {
            ToolbarItem(placement: phoneToolbarPlacement) {
                Button {
                    store.presentNewTask()
                } label: {
                    Image(systemName: "plus")
                }
            }
        }
    }
}
#endif

struct HeaderBar: View {
    @ObservedObject var store: TimeTrackerStore
    let compact: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(AppStrings.today)
                .font(compact ? .largeTitle.bold() : .largeTitle.bold())
            Text(.app("home.subtitle"))
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }
}
