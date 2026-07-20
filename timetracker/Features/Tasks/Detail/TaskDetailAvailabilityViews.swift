import SwiftUI

struct TaskDetailTrackingAvailabilitySection: View {
    let store: TimeTrackerStore
    let task: TaskNode

    @ViewBuilder
    var body: some View {
        if !store.isTaskVisible(task) {
            Section {
                Label(AppStrings.localized("status.archived"), systemImage: "archivebox")
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("task.detail.trackingUnavailable")
            } footer: {
                Text(.app("task.archived.trackingUnavailable"))
            }
        }
    }
}

struct TaskDetailDraftRecoverySection: View {
    let validation: TaskEditorValidation
    let reason: TaskDraftRecoveryReason
    let saveAsNew: () -> Void
    let restoreOriginal: () -> Void
    let discard: () -> Void

    var body: some View {
        Section {
            Label(
                AppStrings.localized("task.editor.recovery.title"),
                systemImage: reason.systemImage
            )
            .font(.headline)
            .foregroundStyle(.orange)

            Text(.app(reason.messageKey))
                .font(.subheadline)
                .foregroundStyle(.secondary)

            if reason == .sourceArchived {
                Button(action: restoreOriginal) {
                    Label(
                        AppStrings.localized(
                            "task.editor.recovery.restoreOriginal"
                        ),
                        systemImage: "arrow.uturn.backward.circle"
                    )
                }
                .accessibilityIdentifier(
                    "task.editor.recovery.restoreOriginal"
                )
            }

            Button(action: saveAsNew) {
                Label(
                    AppStrings.localized("task.editor.recovery.saveAsNew"),
                    systemImage: "doc.badge.plus"
                )
            }
            .disabled(validation.isValid == false)
            .accessibilityIdentifier("task.editor.recovery.saveAsNew")

            Button(role: .destructive, action: discard) {
                Label(
                    AppStrings.localized("task.editor.recovery.discard"),
                    systemImage: "trash"
                )
            }
            .accessibilityIdentifier("task.editor.recovery.discard")
        }
        .accessibilityIdentifier("task.editor.recovery")
    }
}

struct TaskDetailDraftRecoveryLoadingView: View {
    var body: some View {
        ProgressView()
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .accessibilityIdentifier("task.detail.recovery.loading")
    }
}

struct TaskDetailDraftRecoveryLoadFailureView: View {
    let retry: () -> Void

    var body: some View {
        ContentUnavailableView {
            Label(
                AppStrings.localized("task.editor.recovery.loadFailed.title"),
                systemImage: "doc.badge.clock"
            )
        } description: {
            Text(.app("task.editor.recovery.loadFailed.message"))
        } actions: {
            Button(
                AppStrings.localized("action.retry"),
                action: retry
            )
            .buttonStyle(.borderedProminent)
            .accessibilityIdentifier("task.detail.recovery.retry")
        }
        .accessibilityIdentifier("task.detail.recovery.loadFailed")
    }
}

struct TaskDetailRecoveryList: View {
    let store: TimeTrackerStore
    let session: TaskEditorSession
    let reason: TaskDraftRecoveryReason
    let isAwaitingCleanup: Bool
    let isFinishingCleanup: Bool
    let focusedTextField: FocusState<TaskEditorTextField?>.Binding
    let focusedChecklistDraftID: FocusState<UUID?>.Binding
    let saveAsNew: () -> Void
    let restoreOriginal: () -> Void
    let leaveCleanup: () -> Void
    let discard: () -> Void

    var body: some View {
        @Bindable var session = session

        List {
            if isAwaitingCleanup {
                TaskDraftRecoveryCleanupSection(
                    isRetrying: isFinishingCleanup,
                    retry: saveAsNew,
                    close: leaveCleanup
                )
            } else {
                TaskDetailDraftRecoverySection(
                    validation: session.validation,
                    reason: reason,
                    saveAsNew: saveAsNew,
                    restoreOriginal: restoreOriginal,
                    discard: discard
                )
                TaskEditorSections(
                    store: store,
                    draft: $session.draft,
                    validation: session.validation,
                    parentCandidates: session.parentCandidates,
                    focusedTextField: focusedTextField,
                    focusedChecklistDraftID: focusedChecklistDraftID,
                    orderedChecklistIndices: session.orderedChecklistIndices,
                    moveChecklistItems: session.moveChecklistItems,
                    addChecklistItem: addChecklistItem,
                    showsTitleField: true,
                    notesStartInPreview: true
                )
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
        .accessibilityIdentifier("task.detail.recovery")
    }

    private func addChecklistItem(after visualIndex: Int?) {
        focusedChecklistDraftID.wrappedValue = session.addChecklistItem(
            afterVisualIndex: visualIndex
        )
    }
}
