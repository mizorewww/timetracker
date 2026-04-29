import SwiftUI
#if os(iOS)
import UIKit
#endif

struct DesktopMainView: View {
    @ObservedObject var store: TimeTrackerStore

    var body: some View {
        GeometryReader { proxy in
            let compact = proxy.size.width < 720
            ScrollView {
                VStack(alignment: .leading, spacing: compact ? 16 : 22) {
                    HeaderBar(store: store, compact: compact)
                    MetricsAndActions(store: store, horizontal: !compact)
                    TimeProgressSection(store: store)
                    TaskForecastSummarySection(store: store)
                    ActiveTimersSection(store: store)
                    PausedSessionsSection(store: store)
                    if !compact {
                        QuickStartSection(store: store)
                    }
                    TimelineSection(store: store)
                }
                .padding(compact ? 18 : 28)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .background(AppColors.background)
            #if os(iOS)
            .scrollBounceBehavior(.basedOnSize)
            #endif
        }
        .toolbar {
            ToolbarItemGroup {
                Button {
                    store.presentNewTask()
                } label: {
                    Label(AppStrings.newTask, systemImage: "plus")
                }

                Button {
                    store.presentManualTime()
                } label: {
                    Label(AppStrings.addTime, systemImage: "calendar.badge.plus")
                }

                Button {
                    store.refreshQuietly()
                } label: {
                    Label(AppStrings.refresh, systemImage: "arrow.clockwise")
                }
            }
        }
    }
}

struct PhoneHomeView: View {
    @ObservedObject var store: TimeTrackerStore

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                MetricsAndActions(store: store, horizontal: false)
                TimeProgressSection(store: store)
                TaskForecastSummarySection(store: store)
                ActiveTimersSection(store: store)
                PausedSessionsSection(store: store)
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
        .scrollBounceBehavior(.basedOnSize)
        #endif
        #if os(iOS)
        .navigationBarTitleDisplayMode(.large)
        #endif
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
