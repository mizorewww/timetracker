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
                            .padding(14)
                        if segment.id != lastActiveSegmentID {
                            Divider()
                                .padding(.horizontal, 14)
                        }
                    }
                    Divider()
                        .padding(.horizontal, 14)
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
                    TodayTimelineChart(
                        store: store,
                        segments: segments,
                        compactHeight: 320
                    )
                    .padding(16)

                    Divider()

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

struct TodayTimelineChart: View {
    let store: TimeTrackerStore
    let segments: [TimeSegment]
    var compactHeight: CGFloat = 320

    var body: some View {
        TimelineView(.periodic(from: .now, by: 60)) { context in
            TimelineChart(
                timeline: store.timelineSnapshot(
                    segments: segments,
                    date: context.date,
                    now: context.date
                ),
                compactHeight: compactHeight
            )
        }
        .accessibilityIdentifier("home.timeline.graph")
    }
}
