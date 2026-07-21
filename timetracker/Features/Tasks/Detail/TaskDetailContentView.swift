import SwiftUI

struct TaskDetailList: View {
    let store: TimeTrackerStore
    let task: TaskNode
    let session: TaskEditorSession
    let autosaveController: TaskDetailAutosaveController
    let focusedTextField: FocusState<TaskEditorTextField?>.Binding
    let focusedChecklistDraftID: FocusState<UUID?>.Binding
    let snapshot: TaskAnalyticsSnapshot?
    @Binding var range: AnalyticsRange
    let isRefreshing: Bool
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

            if let snapshot {
                TaskDetailOverviewSection(snapshot: snapshot)
                TaskDetailAnalysisSection(
                    range: $range,
                    snapshot: snapshot,
                    isRefreshing: isRefreshing
                )
                TaskDetailRecordsSection(records: snapshot.recentRecords)
            } else {
                Section(AppStrings.localized("task.detail.analysis")) {
                    HStack(spacing: 12) {
                        ProgressView()
                        Text(AppStrings.localized("analytics.loading"))
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .accessibilityIdentifier("task.detail.analyticsLoading")
                }
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
        case .available(let detail):
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
}
