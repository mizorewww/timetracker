import Foundation
import SwiftData

extension TimeTrackerStore {
    func saveManualTimeDraft(_ draft: ManualTimeDraft) throws {
        guard let taskID = draft.taskID else {
            throw StoreError.taskSelectionRequired
        }
        guard draft.endedAt > draft.startedAt else {
            throw StoreError.invalidTimeRange
        }
        guard trackableTaskIDs.contains(taskID) else {
            throw StoreError.taskTrackingUnavailable
        }
        try performStoreCommand(
            onError: handleSegmentMutationFailure,
            command: { session in
                try StoreScopedSegmentCommandCoordinator(
                    session: session
                ).addManualTime(draft: draft, taskID: taskID)
            },
            finish: { _ in
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
            }
        )
    }

    func deleteSegment(
        _ segmentID: UUID,
        expectedBaseline: SegmentEditorDraftBaseline? = nil
    ) throws {
        do {
            try commitSegmentDeletion(
                segmentID,
                expectedBaseline: expectedBaseline
            )
        } catch {
            handleSegmentMutationFailure(error)
            throw error
        }
    }

    func commitSegmentDraft(_ draft: SegmentEditorDraft) throws {
        guard let taskID = draft.taskID else {
            throw StoreError.taskSelectionRequired
        }
        let outcome = try StoreScopedSegmentCommandCoordinator(
            session: requireMutationSession()
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
        let outcome = try StoreScopedSegmentCommandCoordinator(
            session: requireMutationSession()
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
        guard needsRefresh else { return }
        do {
            try refreshSegmentEditorReadModels()
        } catch {
            logReadModelRefreshFailure(error)
        }
    }
}
