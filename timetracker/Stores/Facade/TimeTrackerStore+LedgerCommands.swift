import Foundation
import SwiftData

extension TimeTrackerStore {
    @discardableResult
    func saveManualTimeDraft(_ draft: ManualTimeDraft) -> Bool {
        guard let taskID = draft.taskID else {
            fail(.taskSelectionRequired)
            return false
        }
        guard draft.endedAt > draft.startedAt else {
            fail(.invalidTimeRange)
            return false
        }
        guard trackableTaskIDs.contains(taskID) else {
            fail(.taskTrackingUnavailable)
            return false
        }
        guard let modelContext else {
            errorMessage = StoreError.notConfigured.localizedDescription
            return false
        }
        do {
            try StoreScopedSegmentCommandCoordinator(
                container: modelContext.container,
                writeAuthorization: writeAuthorization
            ).addManualTime(draft: draft, taskID: taskID)
            finishStoreScopedMutation(events: [
                .ledgerChanged(
                    taskID: taskID,
                    dateInterval: StoreInvalidationRange(
                        start: draft.startedAt,
                        end: draft.endedAt
                    ),
                    isVisible: false
                ),
            ])
            return true
        } catch {
            handleSegmentMutationFailure(error)
            return false
        }
    }

    @discardableResult
    func saveSegmentDraft(_ draft: SegmentEditorDraft) -> Bool {
        do {
            try commitSegmentDraft(draft)
            return true
        } catch {
            handleSegmentMutationFailure(error)
            return false
        }
    }

    @discardableResult
    func deleteSegment(
        _ segmentID: UUID,
        expectedBaseline: SegmentEditorDraftBaseline? = nil
    ) -> Bool {
        do {
            try commitSegmentDeletion(
                segmentID,
                expectedBaseline: expectedBaseline
            )
            return true
        } catch {
            handleSegmentMutationFailure(error)
            return false
        }
    }

    func commitSegmentDraft(_ draft: SegmentEditorDraft) throws {
        guard let taskID = draft.taskID else {
            throw StoreError.taskSelectionRequired
        }
        guard let modelContext else {
            throw StoreError.notConfigured
        }
        let outcome = try StoreScopedSegmentCommandCoordinator(
            container: modelContext.container,
            writeAuthorization: writeAuthorization
        ).update(
            draft: draft,
            taskID: taskID
        )
        finishStoreScopedPomodoroMutation(
            events: outcome.events,
            referencedTaskIDs: outcome.referencedTaskIDs
        )
    }

    func commitSegmentDeletion(
        _ segmentID: UUID,
        expectedBaseline: SegmentEditorDraftBaseline?
    ) throws {
        guard let modelContext else {
            throw StoreError.notConfigured
        }
        let outcome = try StoreScopedSegmentCommandCoordinator(
            container: modelContext.container,
            writeAuthorization: writeAuthorization
        ).delete(segmentID: segmentID, expectedBaseline: expectedBaseline)
        finishStoreScopedPomodoroMutation(
            events: outcome.events,
            referencedTaskIDs: outcome.referencedTaskIDs
        )
    }

    func refreshSegmentEditorReadModels() throws {
        try refresh(
            plan: StoreRefreshPlan(
                scopes: [.tasks, .ledgerHistory, .pomodoro]
            )
        )
    }

    private func handleSegmentMutationFailure(_ error: Error) {
        let needsRefresh: Bool = if let mutationError = error as? SegmentMutationError {
            mutationError == .staleDraft ||
                mutationError == .inconsistentSession
        } else {
            error as? TimeTrackingRepositoryError == .taskUnavailable
        }
        guard needsRefresh else {
            errorMessage = error.localizedDescription
            return
        }

        do {
            try refreshSegmentEditorReadModels()
            errorMessage = error.localizedDescription
        } catch let refreshError {
            errorMessage = String(
                format: AppStrings.localized("error.savedRefreshFailed"),
                refreshError.localizedDescription
            )
        }
    }
}
