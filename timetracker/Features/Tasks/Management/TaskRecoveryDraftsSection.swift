import SwiftUI

struct TaskRecoveryDraftsSection: View {
    let store: TimeTrackerStore
    @Environment(AppPresentationRouter.self) private var presentationRouter
    @State private var records: [TaskDraftRecoveryRecord] = []
    @State private var loadFailed = false
    @State private var reloadRequestID = UUID()
    @State private var pendingDiscardID: UUID?
    @State private var discardingIDs: Set<UUID> = []

    var body: some View {
        Group {
            if orphanedRecords.isEmpty == false {
                Section {
                    ForEach(orphanedRecords) { record in
                        recoveryRow(record)
                    }
                    if loadFailed {
                        retryButton
                    }
                } header: {
                    Label(
                        AppStrings.localized("tasks.recovery.title"),
                        systemImage: "doc.badge.clock"
                    )
                } footer: {
                    Text(.app("tasks.recovery.footer"))
                }
            } else if loadFailed {
                Section {
                    retryButton
                } header: {
                    Label(
                        AppStrings.localized("tasks.recovery.title"),
                        systemImage: "doc.badge.clock"
                    )
                }
            }
        }
        .task(id: reloadRequestID) {
            await reload()
        }
        .onChange(of: presentationRouter.sheet?.id) { _, sheetID in
            guard sheetID == nil else { return }
            reloadRequestID = UUID()
        }
        .confirmationDialog(
            AppStrings.localized("tasks.recovery.discard.confirm.title"),
            isPresented: discardConfirmationBinding,
            titleVisibility: .visible
        ) {
            Button(
                AppStrings.localized("task.editor.recovery.discard"),
                role: .destructive,
                action: discardPendingRecord
            )
            Button(AppStrings.cancel, role: .cancel) {
                pendingDiscardID = nil
            }
        } message: {
            Text(.app("tasks.recovery.discard.confirm.message"))
        }
    }

    private var orphanedRecords: [TaskDraftRecoveryRecord] {
        records.filter {
            store.isTaskDetailRouteValid($0.sourceTaskID) == false
        }
    }

    private var retryButton: some View {
        Button {
            reloadRequestID = UUID()
        } label: {
            Label(
                AppStrings.localized("action.retry"),
                systemImage: "arrow.clockwise"
            )
        }
        .accessibilityIdentifier("tasks.recovery.retry")
    }

    private var discardConfirmationBinding: Binding<Bool> {
        Binding {
            pendingDiscardID != nil
        } set: { isPresented in
            if isPresented == false {
                pendingDiscardID = nil
            }
        }
    }

    private func recoveryRow(
        _ record: TaskDraftRecoveryRecord
    ) -> some View {
        HStack(spacing: 0) {
            Button {
                presentationRouter.presentRecoveredTaskDraft(
                    record,
                    using: store
                )
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: "doc.text")
                        .foregroundStyle(.orange)
                        .frame(width: 24, height: 24)

                    VStack(alignment: .leading, spacing: 3) {
                        Text(displayTitle(for: record))
                            .font(.body)
                            .foregroundStyle(.primary)
                            .lineLimit(2)
                        Text(record.savedAt, style: .relative)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        if store.task(for: record.draft.id) != nil {
                            Text(.app("tasks.recovery.cleanupPending"))
                                .font(.caption)
                                .foregroundStyle(.green)
                        } else if store.task(for: record.sourceTaskID) != nil {
                            Text(.app("tasks.recovery.originalArchived"))
                                .font(.caption)
                                .foregroundStyle(.orange)
                        }
                    }
                    Spacer(minLength: 8)
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.tertiary)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityHint(
                AppStrings.localized("tasks.recovery.reviewHint")
            )
            .accessibilityIdentifier("tasks.recovery.review")

            if discardingIDs.contains(record.sourceTaskID) {
                ProgressView()
                    .controlSize(.small)
                    .frame(width: 44, height: 44)
            } else {
                Menu {
                    if store.task(for: record.sourceTaskID) != nil {
                        Button {
                            restoreOriginal(for: record)
                        } label: {
                            Label(
                                AppStrings.localized(
                                    "task.editor.recovery.restoreOriginal"
                                ),
                                systemImage: "arrow.uturn.backward.circle"
                            )
                        }
                    }
                    discardButton(for: record)
                } label: {
                    Label(
                        AppStrings.localized("common.more"),
                        systemImage: "ellipsis.circle"
                    )
                    .labelStyle(.iconOnly)
                    .frame(width: 44, height: 44)
                }
                .accessibilityIdentifier("tasks.recovery.more")
            }
        }
        .disabled(discardingIDs.contains(record.sourceTaskID))
        .swipeActions {
            discardButton(for: record)
        }
        .contextMenu {
            discardButton(for: record)
        }
    }

    private func discardButton(
        for record: TaskDraftRecoveryRecord
    ) -> some View {
        Button(role: .destructive) {
            pendingDiscardID = record.sourceTaskID
        } label: {
            Label(
                AppStrings.localized("task.editor.recovery.discard"),
                systemImage: "trash"
            )
        }
    }

    private func displayTitle(
        for record: TaskDraftRecoveryRecord
    ) -> String {
        let title = record.draft.title.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        return title.isEmpty
            ? AppStrings.localized("tasks.recovery.untitled")
            : title
    }

    private func restoreOriginal(
        for record: TaskDraftRecoveryRecord
    ) {
        guard store.restoreArchivedHierarchyForRecovery(
            taskID: record.sourceTaskID
        ) else { return }
        store.openTaskDetail(record.sourceTaskID)
    }

    private func reload() async {
        do {
            let loadedRecords = try await store
                .taskDraftRecoveryController
                .recoverableRecords()
            guard Task.isCancelled == false else { return }
            records = loadedRecords
            loadFailed = false
        } catch is CancellationError {
            return
        } catch {
            loadFailed = true
        }
    }

    private func discardPendingRecord() {
        guard let sourceTaskID = pendingDiscardID else { return }
        pendingDiscardID = nil
        discardingIDs.insert(sourceTaskID)
        Task {
            defer { discardingIDs.remove(sourceTaskID) }
            do {
                try await store.taskDraftRecoveryController
                    .removeInBackground(for: sourceTaskID)
                records.removeAll { $0.sourceTaskID == sourceTaskID }
            } catch {
                store.errorMessage = TaskDraftRecoveryErrorPresentation
                    .removalFailureMessage(for: error)
            }
        }
    }
}
