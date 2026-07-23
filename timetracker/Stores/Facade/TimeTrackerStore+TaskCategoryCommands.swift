import Foundation
import SwiftData

extension TimeTrackerStore {
    @discardableResult
    func reorderTaskCategories(orderedCategoryIDs: [UUID]) -> Bool {
        reorderTaskCategories(
            orderedCategoryIDs: orderedCategoryIDs,
            baseline: TaskCategoryOrderMutationBaseline(
                categories: taskCategories
            )
        )
    }

    @discardableResult
    func reorderTaskCategories(
        orderedCategoryIDs: [UUID],
        baseline: TaskCategoryOrderMutationBaseline
    ) -> Bool {
        guard let modelContext else {
            errorMessage = StoreError.notConfigured.localizedDescription
            return false
        }
        do {
            let outcome = try StoreScopedTaskCategoryCommandCoordinator(
                container: modelContext.container,
                writeAuthorization: writeAuthorization
            ).reorder(
                orderedCategoryIDs: orderedCategoryIDs,
                baseline: baseline
            )
            finishStoreScopedMutation(events: outcome.events)
            return true
        } catch {
            handleStoreScopedTaskCategoryError(error)
            return false
        }
    }

    @discardableResult
    func saveTaskCategoryDraft(_ draft: TaskCategoryEditorDraft) -> Bool {
        let sanitizedTitle = draft.title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !sanitizedTitle.isEmpty else {
            return fail(.taskCategoryNameRequired)
        }

        guard let modelContext else {
            errorMessage = StoreError.notConfigured.localizedDescription
            return false
        }
        var preparedDraft = draft
        preparedDraft.title = sanitizedTitle
        do {
            let outcome = try StoreScopedTaskCategoryCommandCoordinator(
                container: modelContext.container,
                writeAuthorization: writeAuthorization
            ).save(draft: preparedDraft)
            finishStoreScopedMutation(events: outcome.events)
            return true
        } catch {
            handleStoreScopedTaskCategoryError(error)
            return false
        }
    }

    @discardableResult
    func deleteTaskCategory(_ category: TaskCategory) -> Bool {
        deleteTaskCategory(baseline: TaskCategoryMutationBaseline(category: category))
    }

    @discardableResult
    func deleteTaskCategory(baseline: TaskCategoryMutationBaseline) -> Bool {
        guard let modelContext else {
            errorMessage = StoreError.notConfigured.localizedDescription
            return false
        }
        do {
            let outcome = try StoreScopedTaskCategoryCommandCoordinator(
                container: modelContext.container,
                writeAuthorization: writeAuthorization
            ).delete(baseline: baseline)
            finishStoreScopedMutation(events: outcome.events)
            return true
        } catch {
            handleStoreScopedTaskCategoryError(error)
            return false
        }
    }

    private func handleStoreScopedTaskCategoryError(_ error: Error) {
        if error is StoreScopedTaskCategoryMutationError ||
            (error as? TaskRepositoryError) == .categoryUnavailable {
            do {
                try refresh(plan: StoreRefreshPlan(scopes: [.tasks]))
            } catch {
                errorMessage = String(
                    format: AppStrings.localized("error.savedRefreshFailed"),
                    error.localizedDescription
                )
                return
            }
        }
        errorMessage = error.localizedDescription
    }
}
