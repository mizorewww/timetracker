import SwiftUI

struct TaskDetailList: View {
    let store: TimeTrackerStore
    let task: TaskNode
    let session: TaskEditorSession
    let autosaveController: TaskDetailAutosaveController
    let focusedTextField: FocusState<TaskEditorTextField?>.Binding
    let focusedChecklistDraftID: FocusState<UUID?>.Binding
    let snapshot: TaskAnalyticsSnapshot?
    let analyticsState: TaskDetailAnalyticsLoadState
    let isAppleHealthTask: Bool
    @Binding var range: AnalyticsRange
    @Binding var referenceDate: Date
    let liveNow: Date
    @Binding var monthNavigationAnchor: AnalyticsMonthNavigationAnchor?
    let isRefreshing: Bool
    let retryAnalytics: () -> Void
    @State private var quantityEditorRoute:
        TaskQuantityEntryEditorRoute?

    var body: some View {
        @Bindable var session = session

        List {
            Section {
                TaskDetailIdentityRow(
                    store: store,
                    task: task,
                    draft: $session.draft,
                    validation: session.validation,
                    focusedTextField: focusedTextField
                )
            }

            TaskDetailTrackingAvailabilitySection(store: store, task: task)
            if isAppleHealthTask {
                analyticsContent
            }
            TaskDetailQuantitySections(
                readModel: store.taskQuantityDetail(for: task.id),
                addEntry: { _ in presentQuantityEntryEditor() },
                editEntry: { _, entry in
                    presentQuantityEntryEditor(entryID: entry.id)
                }
            )
            TaskDetailHeatmapTrackingSection(
                store: store,
                task: task,
                colorHex: session.draft.colorHex
            )
            TaskDetailAutosaveFailureSection(
                controller: autosaveController
            )

            TaskEditorSections(
                store: store,
                draft: $session.draft,
                validation: session.validation,
                parentCandidates: session.parentCandidates,
                focusedTextField: focusedTextField,
                focusedChecklistDraftID: focusedChecklistDraftID,
                orderedChecklistIndices: session.orderedChecklistIndices,
                toggleChecklistItem: { id in
                    session.toggleChecklistItem(id: id)
                },
                moveChecklistItems: { sourceOffsets, destination in
                    session.moveChecklistItems(
                        fromOffsets: sourceOffsets,
                        toOffset: destination
                    )
                },
                addChecklistItem: { visualIndex in
                    focusedChecklistDraftID.wrappedValue = session.addChecklistItem(
                        afterVisualIndex: visualIndex
                    )
                },
                showsTitleField: false,
                notesInteractionStyle: .expandablePreview
            )
            TaskDetailForecastSection(store: store, task: task)
            if isAppleHealthTask == false {
                analyticsContent
            }
        }
        #if os(iOS)
        .listStyle(.insetGrouped)
        .scrollDismissesKeyboard(.interactively)
        #else
        .listStyle(.inset)
        #endif
        .contentMargins(.bottom, 16, for: .scrollContent)
        .scrollContentBackground(.hidden)
        .background(AppColors.background)
        .accessibilityIdentifier("task.detail")
        .sheet(item: $quantityEditorRoute) { route in
            TaskQuantityEntryEditorSheet(store: store, route: route)
        }
    }

    private func presentQuantityEntryEditor(entryID: UUID? = nil) {
        guard autosaveController.flush(
            session: session,
            isEnabled: true
        ) else {
            return
        }
        focusedTextField.wrappedValue = nil
        focusedChecklistDraftID.wrappedValue = nil

        switch store.taskQuantityDetail(for: task.id) {
        case .none:
            store.errorMessage = TaskQuantityEntryMutationError
                .quantityGoalUnavailable.localizedDescription
        case .incomplete:
            store.errorMessage = TaskQuantityEntryMutationError
                .incompleteQuantityGraph.localizedDescription
        case let .available(detail):
            if let entryID {
                guard let entry = detail.entries.first(where: {
                    $0.id == entryID
                }) else {
                    store.errorMessage = TaskQuantityEntryMutationError
                        .entryUnavailable.localizedDescription
                    return
                }
                quantityEditorRoute = .edit(
                    detail: detail,
                    entry: entry
                )
                return
            }
            guard detail.progress.isRecordingAllowed else {
                store.errorMessage = recordingUnavailableMessage(
                    role: detail.recurrenceRole
                )
                return
            }
            quantityEditorRoute = .add(detail: detail)
        }
    }

    private func recordingUnavailableMessage(
        role: TaskQuantityRecurrenceRole
    ) -> String {
        if case .template = role {
            return TaskQuantityEntryMutationError
                .recurrenceTemplateRequiresGeneratedTask
                .localizedDescription
        }
        return TaskQuantityEntryMutationError.taskUnavailable
            .localizedDescription
    }

    @ViewBuilder
    private var analyticsContent: some View {
        if isAppleHealthTask, analyticsState != .unavailable {
            TaskDetailAppleHealthPeriodSection(
                range: $range,
                referenceDate: $referenceDate,
                liveNow: liveNow,
                monthNavigationAnchor: $monthNavigationAnchor
            )
        }

        if let snapshot {
            if isAppleHealthTask, analyticsState == .failed {
                TaskDetailAppleHealthFailureSection(retry: retryAnalytics)
            } else if isAppleHealthTask, analyticsState == .unavailable {
                TaskDetailAppleHealthUnavailableSection()
            }

            TaskDetailOverviewSection(
                snapshot: snapshot,
                periodTitle: isAppleHealthTask ? selectedPeriodTitle : nil
            )
            TaskDetailAnalysisSection(
                range: $range,
                snapshot: snapshot,
                isRefreshing: isRefreshing,
                retryAppleHealth: retryAnalytics
            )
            TaskDetailRecordsSection(
                records: snapshot.recentRecords,
                source: snapshot.source
            )
        } else {
            switch analyticsState {
            case .loading, .content:
                TaskDetailAnalyticsLoadingSection(
                    isAppleHealthTask: isAppleHealthTask
                )
            case .empty:
                TaskDetailAppleHealthEmptySection(retry: retryAnalytics)
            case .unavailable:
                TaskDetailAppleHealthUnavailableSection()
            case .failed:
                TaskDetailAppleHealthFailureSection(retry: retryAnalytics)
            }
        }
    }

    private var selectedPeriodTitle: String {
        AnalyticsPeriodText.title(
            for: range,
            date: referenceDate,
            liveNow: liveNow
        )
    }
}

private struct TaskDetailAnalyticsLoadingSection: View {
    let isAppleHealthTask: Bool

    var body: some View {
        Section(AppStrings.localized("task.detail.analysis")) {
            HStack(spacing: 12) {
                ProgressView()
                Text(
                    AppStrings.localized(
                        isAppleHealthTask
                            ? "task.detail.appleHealth.loading"
                            : "analytics.loading"
                    )
                )
                .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityIdentifier(
                isAppleHealthTask
                    ? "task.detail.appleHealth.loading"
                    : "task.detail.analyticsLoading"
            )
        }
    }
}

private struct TaskDetailAppleHealthEmptySection: View {
    let retry: () -> Void

    var body: some View {
        Section(AppStrings.localized("task.detail.appleHealth.section")) {
            Label(
                AppStrings.localized("task.detail.appleHealth.empty.title"),
                systemImage: "heart.text.square"
            )
            .accessibilityIdentifier("task.detail.appleHealth.empty")

            Text(.app("task.detail.appleHealth.empty.message"))
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .accessibilityIdentifier(
                    "task.detail.appleHealth.empty.message"
                )

            TaskDetailAppleHealthRetryButton(action: retry)
        }
    }
}

private struct TaskDetailAppleHealthUnavailableSection: View {
    var body: some View {
        Section(AppStrings.localized("task.detail.appleHealth.section")) {
            Label(
                AppStrings.localized(
                    "task.detail.appleHealth.unavailable.title"
                ),
                systemImage: "heart.slash"
            )
            .accessibilityIdentifier("task.detail.appleHealth.unavailable")

            Text(.app("task.detail.appleHealth.unavailable.message"))
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }
}

private struct TaskDetailAppleHealthFailureSection: View {
    let retry: () -> Void

    var body: some View {
        Section(AppStrings.localized("task.detail.appleHealth.section")) {
            Label(
                AppStrings.localized("task.detail.appleHealth.failed.title"),
                systemImage: "exclamationmark.triangle"
            )
            .accessibilityIdentifier("task.detail.appleHealth.failed")

            Text(.app("task.detail.appleHealth.failed.message"))
                .font(.subheadline)
                .foregroundStyle(.secondary)

            TaskDetailAppleHealthRetryButton(action: retry)
        }
    }
}

struct TaskDetailAppleHealthRetryButton: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label(
                AppStrings.localized("action.retry"),
                systemImage: "arrow.clockwise"
            )
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        #if os(iOS)
        .frame(minHeight: 44)
        #endif
        .accessibilityIdentifier("task.detail.appleHealth.retry")
    }
}
