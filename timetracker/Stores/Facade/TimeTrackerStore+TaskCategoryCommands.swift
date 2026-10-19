import Foundation
import SwiftData

extension TimeTrackerStore {
    @discardableResult
    func reorderTaskCategories(orderedCategoryIDs: [UUID]) -> Bool {
        performStoreCommand(
            eventsForOutcome: { $0.events },
            onError: handleStoreScopedTaskCategoryError
        ) { session in
            try StoreScopedTaskCategoryCommandCoordinator(session: session)
                .reorder(orderedCategoryIDs: orderedCategoryIDs)
        } != nil
    }

    @discardableResult
    func saveTaskCategoryDraft(_ draft: TaskCategoryEditorDraft) -> Bool {
        let sanitizedTitle = draft.title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !sanitizedTitle.isEmpty else {
            return fail(.taskCategoryNameRequired)
        }

        var preparedDraft = draft
        preparedDraft.title = sanitizedTitle
        return performStoreCommand(
            eventsForOutcome: { $0.events },
            onError: handleStoreScopedTaskCategoryError
        ) { session in
            try StoreScopedTaskCategoryCommandCoordinator(
                session: session
            ).save(draft: preparedDraft)
        } != nil
    }

    @discardableResult
    func deleteTaskCategory(_ category: TaskCategory) -> Bool {
        deleteTaskCategory(baseline: TaskCategoryMutationBaseline(category: category))
    }

    @discardableResult
    func deleteTaskCategory(baseline: TaskCategoryMutationBaseline) -> Bool {
        performStoreCommand(
            eventsForOutcome: { $0.events },
            onError: handleStoreScopedTaskCategoryError
        ) { session in
            try StoreScopedTaskCategoryCommandCoordinator(
                session: session
            ).delete(baseline: baseline)
        } != nil
    }

    private func handleStoreScopedTaskCategoryError(_ error: Error) {
        if error is StoreScopedTaskCategoryMutationError ||
            (error as? TaskRepositoryError) == .categoryUnavailable
        {
            do {
                try refresh(plan: StoreRefreshPlan(scopes: [.tasks]))
            } catch {
                errorMessage = savedRefreshFailedMessage(error)
                return
            }
        }
        errorMessage = error.localizedDescription
    }
}
