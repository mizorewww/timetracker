import Foundation
import SwiftData

extension TimeTrackerStore {
    func reorderTaskCategories(orderedCategoryIDs: [UUID]) throws {
        try performStoreCommand(
            eventsForOutcome: { $0.events },
            onError: handleStoreScopedTaskCategoryError
        ) { session in
            try StoreScopedTaskCategoryCommandCoordinator(session: session)
                .reorder(orderedCategoryIDs: orderedCategoryIDs)
        }
    }

    func saveTaskCategoryDraft(_ draft: TaskCategoryEditorDraft) throws {
        let sanitizedTitle = draft.title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !sanitizedTitle.isEmpty else {
            throw StoreError.taskCategoryNameRequired
        }

        var preparedDraft = draft
        preparedDraft.title = sanitizedTitle
        try performStoreCommand(
            eventsForOutcome: { $0.events },
            onError: handleStoreScopedTaskCategoryError
        ) { session in
            try StoreScopedTaskCategoryCommandCoordinator(
                session: session
            ).save(draft: preparedDraft)
        }
    }

    func deleteTaskCategory(_ category: TaskCategory) throws {
        try deleteTaskCategory(baseline: TaskCategoryMutationBaseline(category: category))
    }

    func deleteTaskCategory(baseline: TaskCategoryMutationBaseline) throws {
        try performStoreCommand(
            eventsForOutcome: { $0.events },
            onError: handleStoreScopedTaskCategoryError
        ) { session in
            try StoreScopedTaskCategoryCommandCoordinator(
                session: session
            ).delete(baseline: baseline)
        }
    }

    private func handleStoreScopedTaskCategoryError(_ error: Error) {
        if error is StoreScopedTaskCategoryMutationError ||
            (error as? TaskRepositoryError) == .categoryUnavailable
        {
            refreshLoggingFailure(plan: StoreRefreshPlan(scopes: [.tasks]))
        }
    }
}
