#if os(iOS)
import SwiftUI

struct PhoneNowSection: View {
    let store: TimeTrackerStore
    let segments: [TimeSegment]
    let allowsParallelTimers: Bool
    let openTask: (UUID) -> Void
    let startTimer: () -> Void

    var body: some View {
        Section {
            if segments.isEmpty {
                Button(action: startTimer) {
                    AppActionLabel(
                        title: AppStrings.startTimer,
                        systemImage: "play.fill",
                        minHeight: 48
                    )
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .listRowBackground(Color.clear)
                .accessibilityIdentifier("home.startTimer")
            } else {
                VStack(spacing: 0) {
                    ForEach(segments, id: \.id) { segment in
                        ActiveTimerRow(
                            store: store,
                            segment: segment,
                            actionLabelStyle: .iconOnly,
                            openTaskDetail: openTask
                        )
                        .padding(12)
                        .accessibilityIdentifier("home.activeTimer.\(segment.id.uuidString)")

                        Divider()
                            .padding(.horizontal, 12)
                    }

                    Button(action: startTimer) {
                        Label {
                            Text(activeTimerActionTitle)
                                .lineLimit(nil)
                                .fixedSize(horizontal: false, vertical: true)
                        } icon: {
                            Image(systemName: activeTimerActionSystemImage)
                        }
                        .font(.body.weight(.medium))
                        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .accessibilityIdentifier("home.startTimer")
                }
                .listRowInsets(EdgeInsets())
                .listRowSeparator(.hidden)
            }
        } header: {
            Text(.app("home.now.title"))
                .accessibilityIdentifier("home.activeTimers")
        } footer: {
            if segments.isEmpty {
                Text(.app("timer.chooseTaskFooter"))
            }
        }
    }

    private var activeTimerActionTitle: String {
        allowsParallelTimers
            ? AppStrings.localized("home.startAnotherTimer")
            : AppStrings.localized("home.switchTimer")
    }

    private var activeTimerActionSystemImage: String {
        allowsParallelTimers ? "plus.circle" : "arrow.left.arrow.right.circle"
    }
}

struct PhoneQuickStartSection: View {
    let store: TimeTrackerStore
    let tasks: [TaskNode]
    let startTimer: () -> Void
    let editQuickStart: () -> Void
    let openTask: (UUID) -> Void

    var body: some View {
        Section {
            VStack(spacing: 0) {
                if tasks.isEmpty {
                    Button(action: startTimer) {
                        Label(AppStrings.startTimer, systemImage: "clock.arrow.circlepath")
                            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)

                    Divider()
                        .padding(.horizontal, 12)
                } else {
                    ForEach(tasks, id: \.id) { task in
                        let activeSegment = store.activeSegment(for: task.id)
                        HomeTimerTaskRow(
                            presentation: store.taskIdentityPresentation(for: task),
                            activeSegment: activeSegment,
                            command: store.timerPickerSelectionCommand(for: task),
                            actionLabelStyle: .iconOnly,
                            openTask: {
                                openTask(task.id)
                            },
                            performTimerAction: {
                                if let activeSegment {
                                    store.stop(segment: activeSegment)
                                } else {
                                    store.performTimerPickerSelection(task)
                                }
                            },
                            taskAccessibilityIdentifier: "home.quickStart.task.\(task.id.uuidString)",
                            actionAccessibilityIdentifier: "home.quickStart.timer.\(task.id.uuidString)"
                        )
                        .padding(12)

                        Divider()
                            .padding(.horizontal, 12)
                    }
                }

                Button(action: editQuickStart) {
                    Label(AppStrings.localized("quickStart.edit"), systemImage: "slider.horizontal.3")
                        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .accessibilityIdentifier("home.quickStart.edit")
            }
            .listRowInsets(EdgeInsets())
            .listRowSeparator(.hidden)
        } header: {
            Text(AppStrings.quickStart)
                .accessibilityIdentifier("home.quickStart")
        } footer: {
            if tasks.isEmpty {
                Text(.app("quickStart.empty.description"))
            }
        }
    }
}

struct PhoneTimelineSection: View {
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
        let entries = Array(timeline.entries.reversed())
        let segmentByID = segments.latestByID()

        Section {
            if timeline.entries.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Label(AppStrings.noTodaySegments, systemImage: "clock")
                        .foregroundStyle(.secondary)
                    Text(.app("empty.noTodaySegments.description"))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                .accessibilityElement(children: .combine)
            } else {
                TodayTimelineChart(
                    store: store,
                    segments: segments,
                    compactHeight: 340
                )

                ForEach(entries) { entry in
                    TodayTimelineEntryRow(
                        store: store,
                        entry: entry,
                        segmentByID: segmentByID,
                        style: .list,
                        showsDivider: false,
                        openTaskDetail: openTask
                    )
                }
            }

            if store.shouldShowAppleHealthTimelineStatusInline {
                AppleHealthTimelineAccessRow(store: store)
            }
        } header: {
            Text(AppStrings.todayTimeline)
                .accessibilityIdentifier("home.timeline")
        }
    }
}

struct PhoneForecastSection: View {
    let store: TimeTrackerStore
    let forecasts: [ForecastDisplayItem]
    let openTask: (UUID) -> Void

    var body: some View {
        Section {
            ForEach(forecasts) { item in
                if let task = store.task(for: item.taskID) {
                    ForecastSummaryRow(
                        store: store,
                        task: task,
                        rollup: item.rollup,
                        openTaskDetail: openTask
                    )
                }
            }
        } header: {
            HStack {
                Text(AppStrings.localized("forecast.today.title"))
                Spacer()
                ForecastInfoButton()
            }
            .accessibilityIdentifier("home.forecasts")
        }
    }
}

struct PhoneCountdownSection: View {
    let events: [CountdownEvent]

    var body: some View {
        Section(AppStrings.localized("settings.countdown")) {
            ForEach(events) { event in
                HomeCountdownRow(event: event)
            }
        }
        .accessibilityIdentifier("home.countdown")
    }
}
#endif
