#if os(iOS)
import SwiftUI

struct PhoneHomeView: View {
    let store: TimeTrackerStore
    let openSettings: () -> Void
    let openTask: (UUID) -> Void
    @State private var isTaskPickerPresented = false
    @State private var isQuickStartEditorPresented = false
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private var quickStartTasks: [TaskNode] {
        let pinned = store.preferences.quickStartTaskIDs
            .compactMap { store.task(for: $0) }
            .filter(store.isTaskAvailableForTracking)
        let recent = store.frequentRecentTasks(
            excluding: Set(pinned.map(\.id)),
            limit: max(0, 6 - pinned.count)
        )
        return Array((pinned + recent).prefix(6))
    }

    private var forecasts: [ForecastDisplayItem] {
        Array(store.forecastDisplayItems().prefix(3))
    }

    private var countdownEvents: [CountdownEvent] {
        store.countdownEvents.sorted { $0.date < $1.date }
    }

    var body: some View {
        List {
            Section {
                if store.activeSegments.isEmpty {
                    Button {
                        isTaskPickerPresented = true
                    } label: {
                        Label(AppStrings.startTimer, systemImage: "play.fill")
                            .font(.headline)
                            .frame(maxWidth: .infinity, minHeight: 44)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .listRowBackground(Color.clear)
                    .accessibilityIdentifier("home.startTimer")
                } else {
                    ForEach(store.activeSegments, id: \.id) { segment in
                        ActiveTimerRow(
                            store: store,
                            segment: segment,
                            openTaskDetail: openTask
                        )
                    }

                    if store.preferences.allowParallelTimers {
                        Button {
                            isTaskPickerPresented = true
                        } label: {
                            Label(AppStrings.localized("home.startAnotherTimer"), systemImage: "plus")
                        }
                        .accessibilityIdentifier("home.startTimer")
                    }
                }
            } header: {
                Text(AppStrings.activeTimers)
            } footer: {
                if store.activeSegments.isEmpty {
                    Text(.app("timer.chooseTaskFooter"))
                }
            }

            Section(AppStrings.localized("analytics.summary.title")) {
                PhoneTodaySummaryRow(store: store)
            }

            Section {
                if quickStartTasks.isEmpty {
                    Button {
                        isTaskPickerPresented = true
                    } label: {
                        Label(AppStrings.localized("quickStart.empty.description"), systemImage: "clock.arrow.circlepath")
                    }
                } else {
                    ForEach(quickStartTasks, id: \.id) { task in
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
                    }
                }

                Button {
                    isQuickStartEditorPresented = true
                } label: {
                    Label(AppStrings.localized("quickStart.edit"), systemImage: "slider.horizontal.3")
                }
            } header: {
                Text(AppStrings.quickStart)
                    .accessibilityIdentifier("home.quickStart")
            } footer: {
                Text(.app("quickStart.defaultHint"))
            }

            if !forecasts.isEmpty {
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
                }
            }

            Section {
                if store.timelineSegments.isEmpty {
                    EmptyStateRow(title: AppStrings.noTodaySegments, icon: "clock")
                } else {
                    ForEach(store.timelineSegments, id: \.id) { segment in
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

            if !countdownEvents.isEmpty {
                Section(AppStrings.localized("settings.countdown")) {
                    ForEach(countdownEvents) { event in
                        HomeCountdownRow(event: event)
                    }
                }
                .accessibilityIdentifier("home.countdown")
            }
        }
        .listStyle(.insetGrouped)
        .contentMargins(.bottom, dynamicTypeSize.isAccessibilitySize ? 112 : 16, for: .scrollContent)
        .scrollDismissesKeyboard(.interactively)
        .scrollContentBackground(.hidden)
        .background(AppColors.background)
        .navigationTitle(AppStrings.today)
        .navigationBarTitleDisplayMode(.large)
        .accessibilityIdentifier("home.view")
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                Button(action: openSettings) {
                    Label(AppStrings.settings, systemImage: "gearshape")
                        .labelStyle(.iconOnly)
                }
                .accessibilityIdentifier("settings.open")

                Button {
                    store.presentNewTask()
                } label: {
                    Label(AppStrings.localized("tasks.newRoot"), systemImage: "plus")
                        .labelStyle(.iconOnly)
                }
                .accessibilityIdentifier("home.toolbar.newTask")
            }
        }
        .sheet(isPresented: $isTaskPickerPresented) {
            NavigationStack {
                TaskStartPicker(store: store) {
                    isTaskPickerPresented = false
                }
            }
            .presentationDetents([.medium, .large])
        }
        .sheet(isPresented: $isQuickStartEditorPresented) {
            QuickStartEditorSheet(
                store: store,
                selectedIDs: store.preferences.quickStartTaskIDs,
                onSave: store.setQuickStartTaskIDs
            )
        }
    }
}
#endif
