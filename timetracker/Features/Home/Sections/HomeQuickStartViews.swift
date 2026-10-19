import SwiftUI

/// Pinned and frequent tasks to start in one tap, as rows in a grouped list
/// section (compact) or a card grid (regular canvas).
struct HomeQuickStartSection: View {
    let store: TimeTrackerStore
    let container: HomeSectionContainer
    let tasks: [TaskNode]
    let openTask: (UUID) -> Void
    let startTimer: () -> Void
    @Environment(AppPresentationRouter.self) private var presentationRouter

    var body: some View {
        switch container {
        case .listSection:
            Section {
                VStack(spacing: 0) {
                    if tasks.isEmpty {
                        HomeTimerPickerButton(
                            mode: store.timerPickerMode,
                            action: startTimer,
                            accessibilityIdentifier: "home.quickStart.startTimer"
                        )

                        Divider()
                            .padding(.horizontal, 12)
                    } else {
                        ForEach(tasks, id: \.id) { task in
                            HomeQuickStartTaskRow(
                                store: store,
                                task: task,
                                actionLabelStyle: .iconOnly,
                                openTask: openTask
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
        case .card:
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text(AppStrings.quickStart)
                        .font(.headline)
                        .accessibilityIdentifier("home.quickStart")
                    Spacer()
                    HomeSectionInformationButton.quickStart
                    Button(action: editQuickStart) {
                        Image(systemName: "slider.horizontal.3")
                    }
                    .buttonStyle(.bordered)
                    .frame(minWidth: 44, minHeight: 44)
                    .accessibilityLabel(AppStrings.localized("quickStart.edit"))
                    .accessibilityIdentifier("home.quickStart.edit")
                    .help(AppStrings.localized("quickStart.edit"))
                }

                if tasks.isEmpty {
                    ContentUnavailableView(
                        AppStrings.localized("quickStart.empty.title"),
                        systemImage: "clock.arrow.circlepath",
                        description: Text(.app("quickStart.empty.description"))
                    )
                    .frame(maxWidth: .infinity, minHeight: 104)
                } else {
                    QuickStartTaskGroup(
                        tasks: tasks,
                        store: store,
                        openTask: openTask
                    )
                }
            }
        }
    }

    private func editQuickStart() {
        presentationRouter.present(
            .quickStartEditor(selectedIDs: store.preferences.quickStartTaskIDs)
        )
    }
}

/// One quick-start task: opens the task, and starts or stops its timer.
struct HomeQuickStartTaskRow: View {
    let store: TimeTrackerStore
    @Environment(AppSceneFeedbackRouter.self) private var feedbackRouter
    let task: TaskNode
    let actionLabelStyle: TaskTimerActionLabelStyle
    let openTask: (UUID) -> Void

    var body: some View {
        let activeSegment = store.activeSegment(for: task.id)
        HomeTimerTaskRow(
            presentation: store.taskIdentityPresentation(for: task),
            activeSegment: activeSegment,
            command: store.timerPickerSelectionCommand(for: task),
            actionLabelStyle: actionLabelStyle,
            openTask: {
                openTask(task.id)
            },
            performTimerAction: {
                feedbackRouter.perform {
                    if let activeSegment {
                        try store.stop(segment: activeSegment)
                    } else {
                        try store.performTimerPickerSelection(task)
                    }
                }
            },
            taskAccessibilityIdentifier: "home.quickStart.task.\(task.id.uuidString)",
            actionAccessibilityIdentifier: "home.quickStart.timer.\(task.id.uuidString)"
        )
    }
}
