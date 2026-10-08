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
    @State private var quantityEditorRoute:
        TaskQuantityEntryEditorRoute?

    var body: some View {
        @Bindable var session = session

        List {
            if session.showsRecoveredDraftNotice {
                Section {
                    TaskDetailRecoveredDraftNotice(
                        dismiss: session.dismissRecoveredDraftNotice
                    )
                }
            }

            Section {
                TaskDetailIdentityRow(
                    store: store,
                    task: task,
                    draft: $session.draft,
                    validation: session.validation,
                    focusedTextField: focusedTextField
                )
            }

            TaskDetailTrackingAvailabilitySection(
                store: store,
                task: task
            )
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
                deleteChecklistItem: { id in
                    session.deleteChecklistItem(id: id)
                },
                moveChecklistItems: { sourceOffsets, destination in
                    session.moveChecklistItems(
                        fromOffsets: sourceOffsets,
                        toOffset: destination
                    )
                },
                addChecklistItem: { visualIndex in
                    focusedChecklistDraftID.wrappedValue = session
                        .addChecklistItem(
                            afterVisualIndex: visualIndex
                        )
                },
                showsTitleField: false,
                notesInteractionStyle: .expandablePreview
            )
            TaskDetailForecastSection(store: store, task: task)
            analyticsContent
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
        if let snapshot {
            TaskDetailOverviewSection(snapshot: snapshot)
            TaskDetailAnalysisSection(
                range: $range,
                snapshot: snapshot
            )
            TaskDetailRecordsSection(
                store: store,
                records: snapshot.recentRecords
            )
        } else {
            TaskDetailAnalyticsLoadingSection()
        }
    }
}

private struct TaskDetailRecoveredDraftNotice: View {
    let dismiss: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(
                AppStrings.localized("task.editor.recovery.title"),
                systemImage: "doc.badge.clock"
            )
            .font(.headline)
            .foregroundStyle(.orange)

            Text(.app("task.editor.recovery.restored.message"))
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Button(AppStrings.localized("common.dismiss"), action: dismiss)
                .accessibilityIdentifier("task.detail.recovery.dismiss")
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("task.detail.recovery.notice")
    }
}

private struct TaskDetailAnalyticsLoadingSection: View {
    var body: some View {
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
