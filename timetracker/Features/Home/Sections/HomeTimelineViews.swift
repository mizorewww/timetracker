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
    let live: TodayLiveSnapshot
    let openTask: (UUID) -> Void

    var body: some View {
        let timeline = live.timeline

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

                    let lastEntryID = live.rows.last?.id
                    ForEach(live.rows) { entry in
                        TodayTimelineEntryRow(
                            store: store,
                            entry: entry,
                            segmentByID: live.segmentByID,
                            showsDivider: entry.id != lastEntryID,
                            openTaskDetail: openTask
                        )
                    }
                }
            }
            .appCard(padding: 0)
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("home.timeline")
    }
}

struct TodayTimelineChart: View {
    let timeline: AnalyticsTimelineSnapshot
    var compactHeight: CGFloat = 320

    var body: some View {
        TimelineChart(
            timeline: timeline,
            compactHeight: compactHeight
        )
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("home.timeline.chart")
    }
}
