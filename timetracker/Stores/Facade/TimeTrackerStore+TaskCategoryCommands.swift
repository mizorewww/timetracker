import Foundation

extension TimeTrackerStore {
    func presentNewTaskCategory() {
        taskCategoryEditorDraft = TaskCategoryEditorDraft()
    }

    func presentEditTaskCategory(_ category: TaskCategory) {
        taskCategoryEditorDraft = TaskCategoryEditorDraft(category: category)
    }

    @discardableResult
    func saveTaskCategoryDraft(_ draft: TaskCategoryEditorDraft) -> Bool {
        let sanitizedTitle = draft.title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !sanitizedTitle.isEmpty else {
            errorMessage = AppStrings.localized("taskCategory.nameRequired")
            return false
        }

        let didSave = perform(event: .taskChanged(taskID: nil, affectedAncestorIDs: [])) {
            let repository = try requiredTaskRepository()
            if let categoryID = draft.categoryID {
                try repository.updateCategory(
                    categoryID: categoryID,
                    title: sanitizedTitle,
                    colorHex: draft.colorHex,
                    iconName: draft.iconName,
                    includesInForecast: draft.includesInForecast
                )
            } else {
                _ = try repository.createCategory(
                    title: sanitizedTitle,
                    colorHex: draft.colorHex,
                    iconName: draft.iconName,
                    includesInForecast: draft.includesInForecast
                )
            }
        }
        if didSave {
            taskCategoryEditorDraft = nil
        }
        return didSave
    }

    func deleteTaskCategory(_ category: TaskCategory) {
        perform(event: .taskChanged(taskID: nil, affectedAncestorIDs: [])) {
            try requiredTaskRepository().softDeleteCategory(categoryID: category.id)
        }
    }
}
