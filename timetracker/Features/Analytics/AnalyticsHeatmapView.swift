import SwiftUI

struct AnalyticsHeatmapView: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    let store: TimeTrackerStore
    @State private var now = Date()

    var body: some View {
        Group {
            if store.todayHeatmapRenderableTaskIDs.isEmpty {
                ContentUnavailableView(
                    AppStrings.localized("analytics.heatmaps.empty.title"),
                    systemImage: "square.grid.3x3",
                    description: Text(
                        .app("analytics.heatmaps.empty.description")
                    )
                )
                .accessibilityIdentifier("analytics.heatmaps.empty")
            } else {
                List {
                    HomeActivityHeatmapSection(
                        store: store,
                        container: .listSection,
                        now: now
                    )
                }
                .appSheetListStyle()
                .contentMargins(
                    .bottom,
                    dynamicTypeSize.isAccessibilitySize ? 112 : 16,
                    for: .scrollContent
                )
                .scrollContentBackground(.hidden)
                .accessibilityIdentifier("analytics.heatmaps.view")
            }
        }
        .background(AppColors.background)
        .liveClock(
            $now,
            until: LiveClockDeadline.next(after: now, isLive: store.activeSegments.isEmpty == false)
        )
        .navigationTitle(
            AnalyticsStandalonePage.heatmaps.destinationTitle
        )
        .appInlineNavigationTitle()
    }
}
