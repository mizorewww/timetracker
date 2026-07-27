import SwiftUI

struct OverlappingTimelineContent: View {
    let store: TimeTrackerStore
    let timeline: AnalyticsTimelineSnapshot
    @Environment(AppPresentationRouter.self) var presentationRouter

    var laneEntries: [AnalyticsTimelineEntry] {
        timeline.entries
    }

    var body: some View {
        if laneEntries.isEmpty {
            EmptyStateRow(title: AppStrings.localized("analytics.timeline.empty"), icon: "timeline.selection")
        } else {
            VStack(alignment: .leading, spacing: 14) {
                TimelineChart(timeline: timeline, compactHeight: 520)

                Divider()

                VStack(spacing: 0) {
                    let lastEntryID = laneEntries.last?.id
                    ForEach(laneEntries) { entry in
                        timelineLegendRow(entry)
                        if entry.id != lastEntryID {
                            Divider()
                        }
                    }
                }
            }
        }
    }
}
