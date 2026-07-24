import SwiftUI

struct ActiveTimersSection: View {
    let store: TimeTrackerStore
    let segments: [TimeSegment]
    let openTask: (UUID) -> Void
    let startTimer: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionTitle(title: AppStrings.localized("home.now.title"))
                .accessibilityIdentifier("home.activeTimers")

            if segments.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    HomeNowEmptyStartButton(startTimer: startTimer)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(14)
                }
                .appCard(padding: 0)
                Text(.app("timer.chooseTaskFooter"))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } else {
                HomeNowActiveContent(
                    store: store,
                    segments: segments,
                    allowsParallelTimers: store.preferences.allowParallelTimers,
                    actionLabelStyle: .titleAndIcon,
                    openTask: openTask,
                    startTimer: startTimer
                )
                .appCard(padding: 0)
            }
        }
    }
}

struct TimelineSection: View {
    let store: TimeTrackerStore
    let segments: [TimeSegment]
    let openTask: (UUID) -> Void

    var body: some View {
        let now = homeTimelineReferenceDate(liveDate: Date())
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
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("home.timeline")
    }
}

struct TodayTimelineChart: View {
    let store: TimeTrackerStore
    let segments: [TimeSegment]
    var compactHeight: CGFloat = 320

    var body: some View {
        TimelineView(.periodic(from: .now, by: 60)) { context in
            let referenceDate = homeTimelineReferenceDate(liveDate: context.date)
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
}

var homeTimelineUsesFixedUITestReferenceDate: Bool {
    #if DEBUG
    CommandLine.arguments.contains("--uitesting-overlap-timeline") ||
        CommandLine.arguments.contains("--uitesting-gap-label-collision")
    #else
    false
    #endif
}

func homeTimelineReferenceDate(liveDate: Date) -> Date {
    #if DEBUG
    guard homeTimelineUsesFixedUITestReferenceDate else {
        return liveDate
    }
    return Calendar.current.startOfDay(for: liveDate)
        .addingTimeInterval(18 * 60 * 60)
    #else
    return liveDate
    #endif
}
