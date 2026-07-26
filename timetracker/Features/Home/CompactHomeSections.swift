import SwiftUI

struct CompactNowSection: View {
    let store: TimeTrackerStore
    let segments: [TimeSegment]
    let allowsParallelTimers: Bool
    let openTask: (UUID) -> Void
    let startTimer: () -> Void

    var body: some View {
        Section {
            if segments.isEmpty {
                HomeNowEmptyStartButton(startTimer: startTimer)
                    .listRowBackground(Color.clear)
            } else {
                HomeNowActiveContent(
                    store: store,
                    segments: segments,
                    allowsParallelTimers: allowsParallelTimers,
                    actionLabelStyle: .iconOnly,
                    openTask: openTask,
                    startTimer: startTimer
                )
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
}

struct CompactQuickStartSection: View {
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
            HStack(alignment: .center, spacing: 4) {
                Text(AppStrings.quickStart)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .accessibilityIdentifier("home.quickStart")
                HomeSectionInformationButton.quickStart
            }
            .textCase(nil)
        } footer: {
            if tasks.isEmpty {
                Text(.app("quickStart.empty.description"))
            }
        }
    }
}

struct CompactTimelineSection: View {
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
                    timeline: timeline,
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

            // HealthKit has no macOS counterpart, so neither does this row.
            #if os(iOS)
            if store.shouldShowAppleHealthTimelineStatusInline {
                AppleHealthTimelineAccessRow(store: store)
            }
            #endif
        } header: {
            Text(AppStrings.todayTimeline)
                .accessibilityIdentifier("home.timeline")
        }
        .task {
            await runHomeTimelineReferenceClock(
                referenceDate: $referenceDate
            )
        }
    }
}

struct CompactForecastSection: View {
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
                    .accessibilityIdentifier("home.forecasts.header")
                Spacer()
                ForecastInfoButton()
            }
        }
    }
}

struct CompactCountdownSection: View {
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
