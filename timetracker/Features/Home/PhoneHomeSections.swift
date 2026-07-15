#if os(iOS)
import SwiftUI

struct PhoneNowSection: View {
    let store: TimeTrackerStore
    let segments: [TimeSegment]
    let allowsParallelTimers: Bool
    let openTask: (UUID) -> Void
    let startTimer: () -> Void
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

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
                ForEach(segments, id: \.id) { segment in
                    ActiveTimerRow(
                        store: store,
                        segment: segment,
                        openTaskDetail: openTask
                    )
                    .accessibilityIdentifier("home.activeTimer.\(segment.id.uuidString)")
                }

                if allowsParallelTimers && !dynamicTypeSize.isAccessibilitySize {
                    Button(action: startTimer) {
                        Label(
                            AppStrings.localized("home.startAnotherTimer"),
                            systemImage: "plus.circle"
                        )
                        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                    }
                    .accessibilityIdentifier("home.startTimer")
                }
            }
        } header: {
            HStack(spacing: 8) {
                Text(.app("home.now.title"))
                    .accessibilityIdentifier("home.activeTimers")
                Spacer()
                if !segments.isEmpty && allowsParallelTimers && dynamicTypeSize.isAccessibilitySize {
                    Button(action: startTimer) {
                        Image(systemName: "plus.circle")
                            .font(.system(size: 20, weight: .semibold))
                            .frame(width: 44, height: 44)
                            .contentShape(.rect)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(Text(.app("home.startAnotherTimer")))
                    .accessibilityIdentifier("home.startTimer")
                }
            }
        } footer: {
            if segments.isEmpty {
                Text(.app("timer.chooseTaskFooter"))
            }
        }
    }
}

struct PhoneQuickStartSection: View {
    let store: TimeTrackerStore
    let tasks: [TaskNode]
    let startTimer: () -> Void
    let editQuickStart: () -> Void

    var body: some View {
        Section {
            if tasks.isEmpty {
                Button(action: startTimer) {
                    Label(AppStrings.startTimer, systemImage: "clock.arrow.circlepath")
                        .frame(minHeight: 44)
                }
            } else {
                ForEach(tasks, id: \.id) { task in
                    let activeSegment = store.activeSegment(for: task.id)
                    PhoneQuickStartRow(
                        task: task,
                        path: store.path(for: task),
                        isRunning: activeSegment != nil
                    ) {
                        if let activeSegment {
                            store.stop(segment: activeSegment)
                        } else {
                            store.startTask(task)
                        }
                    }
                    .accessibilityIdentifier("home.quickStart.task.\(task.id.uuidString)")
                }
            }

            Button(action: editQuickStart) {
                Label(AppStrings.localized("quickStart.edit"), systemImage: "slider.horizontal.3")
                    .frame(minHeight: 44)
            }
            .accessibilityIdentifier("home.quickStart.edit")
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
        Section {
            if segments.isEmpty {
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
                ForEach(segments, id: \.id) { segment in
                    TimelineRow(
                        store: store,
                        segment: segment,
                        openTaskDetail: openTask
                    )
                }
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
