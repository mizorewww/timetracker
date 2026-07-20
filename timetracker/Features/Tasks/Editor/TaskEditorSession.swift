import Foundation
import Observation

@MainActor
@Observable
final class TaskEditorSession {
    @ObservationIgnored let store: TimeTrackerStore

    var draft: TaskEditorDraft
    private(set) var sessionBaseline: TaskEditorDraft
    private(set) var parentCandidates: [TaskNode]
    var pendingReloadDraft: TaskEditorDraft?
    var isDiscardConfirmationPresented = false
    private(set) var navigationConfirmationRequestID: UUID?

    init(store: TimeTrackerStore, initialDraft: TaskEditorDraft) {
        self.store = store
        draft = initialDraft
        sessionBaseline = initialDraft
        parentCandidates = Self.parentCandidates(
            for: initialDraft,
            store: store
        )
    }

    var validation: TaskEditorValidation {
        TaskEditorValidation(
            title: draft.title,
            notes: draft.notes,
            iconName: draft.iconName,
            colorHex: draft.colorHex
        )
    }

    var hasUnsavedChanges: Bool {
        draft != sessionBaseline
    }

    func requestCancel(whenClean: () -> Void) {
        if hasUnsavedChanges {
            navigationConfirmationRequestID = nil
            isDiscardConfirmationPresented = true
        } else {
            whenClean()
        }
    }

    func requestDiscardConfirmation(for navigationRequestID: UUID) {
        navigationConfirmationRequestID = navigationRequestID
        isDiscardConfirmationPresented = true
    }

    func dismissDiscardConfirmation(for navigationRequestID: UUID) {
        guard navigationConfirmationRequestID == navigationRequestID else {
            return
        }
        navigationConfirmationRequestID = nil
        isDiscardConfirmationPresented = false
    }

    func clearNavigationConfirmationRequest(_ navigationRequestID: UUID) {
        guard navigationConfirmationRequestID == navigationRequestID else {
            return
        }
        navigationConfirmationRequestID = nil
    }

    func save(
        using saveDraft: (TaskEditorDraft) -> TaskDraftSaveResult,
        onSaved: (UUID) -> Void,
        onStale: (() -> Void)? = nil
    ) {
        switch saveDraft(draft) {
        case .saved(let taskID):
            onSaved(taskID)
        case .stale:
            if let onStale {
                onStale()
            } else {
                prepareLatestDraft()
            }
        case .failed(let message):
            store.errorMessage = message
        }
    }

    func acceptLatestDraft(for taskID: UUID) {
        guard let task = store.task(for: taskID) else { return }
        replace(with: store.editorDraft(for: task))
    }

    func synchronizeWithStoreIfClean(taskID: UUID) {
        guard hasUnsavedChanges == false else { return }
        acceptLatestDraft(for: taskID)
    }

    func restoreRecoveredDraft(_ recoveredDraft: TaskEditorDraft) {
        guard let sourceTaskID = sessionBaseline.taskID,
              recoveredDraft.taskID == sourceTaskID,
              recoveredDraft.baseline != nil,
              recoveredDraft != sessionBaseline else { return }
        draft = recoveredDraft
        parentCandidates = Self.parentCandidates(
            for: recoveredDraft,
            store: store
        )
        pendingReloadDraft = nil
    }

    func discardChanges() {
        if let taskID = draft.taskID,
           let task = store.task(for: taskID) {
            replace(with: store.editorDraft(for: task))
        } else {
            replace(with: sessionBaseline)
        }
    }

    func reloadLatestDraft() {
        guard let latestDraft = pendingReloadDraft else { return }
        replace(with: latestDraft)
    }

    private func prepareLatestDraft() {
        guard let taskID = draft.taskID,
              let latestTask = store.task(for: taskID) else {
            store.errorMessage = AppStrings.localized(
                "systemAction.error.taskNotFound"
            )
            return
        }
        pendingReloadDraft = store.editorDraft(for: latestTask)
    }

    private func replace(with latestDraft: TaskEditorDraft) {
        draft = latestDraft
        sessionBaseline = latestDraft
        parentCandidates = Self.parentCandidates(
            for: latestDraft,
            store: store
        )
        pendingReloadDraft = nil
    }

    private static func parentCandidates(
        for draft: TaskEditorDraft,
        store: TimeTrackerStore
    ) -> [TaskNode] {
        var candidates = store.validParentTasks(for: draft.taskID)
        if let currentParentID = draft.parentID,
           let currentParent = store.task(for: currentParentID),
           candidates.contains(where: { $0.id == currentParentID }) == false {
            candidates.append(currentParent)
        }
        return candidates
    }
}
