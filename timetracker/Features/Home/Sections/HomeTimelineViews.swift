import SwiftUI

struct ActiveTimersSection: View {
    let store: TimeTrackerStore
    let segments: [TimeSegment]
    let openTask: (UUID) -> Void

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
                        ActiveTimerRow(
                            store: store,
                            segment: segment,
                            actionLabelStyle: .titleAndIcon,
                            openTaskDetail: openTask
                        )
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
    let openTask: (UUID) -> Void

    var body: some View {
        let now = Date()
        let timeline = store.timelineSnapshot(
            segments: segments,
            date: now,
            now: now
        )

        VStack(alignment: .leading, spacing: 10) {
            SectionTitle(title: AppStrings.todayTimeline)

            VStack(spacing: 0) {
                if timeline.entries.isEmpty {
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

                    let entries = Array(timeline.entries.reversed())
                    let segmentByID = segments.latestByID()
                    let lastEntryID = entries.last?.id
                    ForEach(entries) { entry in
                        TodayTimelineEntryRow(
                            store: store,
                            entry: entry,
                            segmentByID: segmentByID,
                            style: .card,
                            showsDivider: entry.id != lastEntryID,
                            openTaskDetail: openTask
                        )
                    }
                }

                #if os(iOS)
                if store.shouldShowAppleHealthTimelineStatusInline {
                    if timeline.entries.isEmpty == false {
                        Divider()
                    }
                    AppleHealthTimelineAccessRow(store: store)
                        .padding(14)
                }
                #endif
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
            let referenceDate = timelineReferenceDate(liveDate: context.date)
            TimelineChart(
                timeline: store.timelineSnapshot(
                    segments: segments,
                    date: referenceDate,
                    now: referenceDate
                ),
                compactHeight: compactHeight,
                exposesUITestingMarks: exposesUITestingMarks
            )
        }
    }

    private var exposesUITestingMarks: Bool {
        #if DEBUG
        CommandLine.arguments.contains("--uitesting-short-timeline") ||
            CommandLine.arguments.contains("--uitesting-overlap-timeline") ||
            CommandLine.arguments.contains("--uitesting-gap-label-collision")
        #else
        false
        #endif
    }

    private func timelineReferenceDate(liveDate: Date) -> Date {
        #if DEBUG
        let usesFixedReferenceDate =
            CommandLine.arguments.contains("--uitesting-overlap-timeline") ||
            CommandLine.arguments.contains("--uitesting-gap-label-collision")
        guard usesFixedReferenceDate else {
            return liveDate
        }
        return Calendar.current.startOfDay(for: liveDate)
            .addingTimeInterval(18 * 60 * 60)
        #else
        return liveDate
        #endif
    }
}
