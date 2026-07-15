import SwiftUI

struct ActiveTimersSection: View {
    let store: TimeTrackerStore
    let segments: [TimeSegment]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionTitle(title: AppStrings.localized("home.now.title"))
                .accessibilityIdentifier("home.activeTimers")

            VStack(spacing: 0) {
                if segments.isEmpty {
                    ContentUnavailableView {
                        Label(AppStrings.noActiveTimers, systemImage: "timer")
                    } description: {
                        Text(.app("timer.chooseTaskFooter"))
                    } actions: {
                        TodayTimerAction(store: store)
                            .frame(minWidth: 220, maxWidth: 320)
                    }
                    .padding(18)
                } else {
                    let lastActiveSegmentID = segments.last?.id
                    ForEach(segments, id: \.id) { segment in
                        ActiveTimerRow(store: store, segment: segment)
                        if segment.id != lastActiveSegmentID {
                            Divider()
                        }
                    }
                    Divider()
                    TodayTimerAction(store: store)
                        .frame(maxWidth: 320)
                        .frame(maxWidth: .infinity, alignment: .trailing)
                        .padding(14)
                }
            }
            .appCard(padding: 0)
        }
    }
}

struct TimelineSection: View {
    let store: TimeTrackerStore
    let segments: [TimeSegment]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionTitle(title: AppStrings.todayTimeline)

            VStack(spacing: 0) {
                if segments.isEmpty {
                    ContentUnavailableView {
                        Label(AppStrings.noTodaySegments, systemImage: "clock")
                    } description: {
                        Text(.app("empty.noTodaySegments.description"))
                    }
                    .padding(18)
                } else {
                    let lastTimelineSegmentID = segments.last?.id
                    ForEach(segments, id: \.id) { segment in
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
