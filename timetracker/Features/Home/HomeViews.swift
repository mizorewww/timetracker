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

struct PhoneHomeView: View {
    @ObservedObject var store: TimeTrackerStore
    @State private var showsSettings = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                MetricsAndActions(store: store, horizontal: false)
                TimeProgressSection(store: store)
                TaskForecastSummarySection(store: store)
                ActiveTimersSection(store: store)
                QuickStartSection(store: store)
                TimelineSection(store: store)
                InspectorSummaryCard(store: store)
            }
            .padding(.horizontal, 18)
            .padding(.top, 0)
            .padding(.bottom, 24)
        }
        .background(AppColors.background)
        .navigationTitle(AppStrings.today)
        #if os(iOS)
        .navigationBarTitleDisplayMode(.large)
        #endif
        .toolbar {
            ToolbarItem(placement: phoneLeadingToolbarPlacement) {
                Button {
                    showsSettings = true
                } label: {
                    Image(systemName: "gearshape")
                }
                .accessibilityLabel(AppStrings.settings)
            }

            ToolbarItem(placement: phoneToolbarPlacement) {
                Button {
                    store.presentNewTask()
                } label: {
                    Image(systemName: "plus")
                }
            }
        }
        .sheet(isPresented: $showsSettings) {
            NavigationStack {
                SettingsView(store: store)
                    .toolbar {
                        ToolbarItem(placement: phoneToolbarPlacement) {
                            Button(AppStrings.done) {
                                showsSettings = false
                            }
                        }
                    }
            }
        }
    }
}

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
