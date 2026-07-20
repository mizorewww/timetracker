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
                notesStartInPreview: true
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
    }
}
