import SwiftUI

struct ActiveTimersSection: View {
    let store: TimeTrackerStore
    let segments: [TimeSegment]
    let openTask: (UUID) -> Void
    let startTimer: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HomeSectionHeader(
                container: .card,
                title: AppStrings.localized("home.now.title"),
                accessibilityIdentifier: "home.activeTimers"
            ) {
                EmptyView()
            }

            if segments.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    HomeTimerPickerButton(
                        mode: store.timerPickerMode,
                        action: startTimer,
                        accessibilityIdentifier: "home.startTimer"
                    )
                }
                .appCard(padding: 0)
                .accessibilityElement(children: .contain)
                .accessibilityIdentifier("home.now.card")
                Text(.app("timer.chooseTaskFooter"))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } else {
                HomeNowActiveContent(
                    store: store,
                    segments: segments,
                    timerPickerMode: store.timerPickerMode,
                    actionLabelStyle: .titleAndIcon,
                    openTask: openTask,
                    startTimer: startTimer
                )
                .appCard(padding: 0)
                .accessibilityElement(children: .contain)
                .accessibilityIdentifier("home.now.card")
            }
        }
    }
}

struct TimelineSection: View {
    let store: TimeTrackerStore
    let segments: [TimeSegment]
    let openTask: (UUID) -> Void
    @State private var referenceDate = homeTimelineReferenceDate(liveDate: Date())

    var body: some View {
        let snapshotReferenceDate = homeTimelineSnapshotReferenceDate(
            clockDate: referenceDate,
            liveDate: Date()
        )
        let timeline = store.timelineSnapshot(
            segments: segments,
            date: snapshotReferenceDate,
            now: snapshotReferenceDate
        )

        VStack(alignment: .leading, spacing: 10) {
            SectionTitle(title: AppStrings.todayTimeline)

            LazyVStack(spacing: 0) {
                if timeline.entries.isEmpty {
                    ContentUnavailableView {
                        Label(AppStrings.noTodaySegments, systemImage: "clock")
                    } description: {
                        Text(.app("empty.noTodaySegments.description"))
                    }
                    .padding(18)
                } else {
                    TodayTimelineChart(
                        timeline: timeline,
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
        .task {
            await runHomeTimelineReferenceClock(
                referenceDate: $referenceDate
            )
        }
    }
}

struct TodayTimelineChart: View {
    let timeline: AnalyticsTimelineSnapshot
    var compactHeight: CGFloat = 320

    var body: some View {
        TimelineChart(
            timeline: timeline,
            compactHeight: compactHeight,
            exposesUITestingMarks: exposesUITestingMarks
        )
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("home.timeline.chart")
    }

    private var exposesUITestingMarks: Bool {
        #if DEBUG
        CommandLine.arguments.contains("--uitesting-short-timeline") ||
            CommandLine.arguments.contains("--uitesting-overlap-timeline") ||
            CommandLine.arguments.contains("--uitesting-gap-label-collision") ||
            CommandLine.arguments.contains(
                "--uitesting-first-health-timeline"
            )
        #else
        false
        #endif
    }
}

@MainActor
func runHomeTimelineReferenceClock(
    referenceDate: Binding<Date>
) async {
    while Task.isCancelled == false {
        do {
            try await Task.sleep(for: .seconds(60))
        } catch {
            return
        }
        let nextReferenceDate = homeTimelineReferenceDate(liveDate: Date())
        guard nextReferenceDate != referenceDate.wrappedValue else { continue }
        referenceDate.wrappedValue = nextReferenceDate
    }
}

var homeTimelineUsesFixedUITestReferenceDate: Bool {
    #if DEBUG
    CommandLine.arguments.contains("--uitesting-overlap-timeline") ||
        CommandLine.arguments.contains("--uitesting-gap-label-collision") ||
        CommandLine.arguments.contains("--uitesting-first-health-timeline")
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

func homeTimelineSnapshotReferenceDate(
    clockDate: Date,
    liveDate: Date
) -> Date {
    #if DEBUG
    if homeTimelineUsesFixedUITestReferenceDate {
        return clockDate
    }
    #endif
    // Ledger mutations can invalidate the view between minute-clock ticks.
    // Never interpret a just-written stop date as a future, still-open end.
    return max(clockDate, liveDate)
}
