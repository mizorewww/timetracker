import SwiftUI

struct ActiveTimersSection: View {
    @ObservedObject var store: TimeTrackerStore

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionTitle(title: AppStrings.activeTimers)

            VStack(spacing: 0) {
                let activeSegments = store.activeSegments
                let lastActiveSegmentID = activeSegments.last?.id
                if activeSegments.isEmpty {
                    EmptyStateRow(title: AppStrings.noActiveTimers, icon: "timer")
                } else {
                    ForEach(activeSegments, id: \.id) { segment in
                        ActiveTimerRow(store: store, segment: segment)
                        if segment.id != lastActiveSegmentID {
                            Divider()
                        }
                    }
                }
            }
            .appCard(padding: 0)
        }
        .accessibilityIdentifier("home.activeTimers")
    }
}

struct TimelineSection: View {
    @ObservedObject var store: TimeTrackerStore

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionTitle(title: AppStrings.todayTimeline)

            VStack(spacing: 0) {
                let timelineSegments = store.timelineSegments
                let lastTimelineSegmentID = timelineSegments.last?.id
                if timelineSegments.isEmpty {
                    EmptyStateRow(title: AppStrings.noTodaySegments, icon: "clock")
                } else {
                    ForEach(timelineSegments, id: \.id) { segment in
                        TimelineRow(store: store, segment: segment)
                        if segment.id != lastTimelineSegmentID {
                            Divider().padding(.leading, 18)
                        }
                    }
                }
            }
            .appCard(padding: 0)
        }
        .accessibilityIdentifier("home.timeline")
    }
}
