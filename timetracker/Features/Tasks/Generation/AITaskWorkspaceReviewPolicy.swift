import Foundation

struct AITaskWorkspaceOperationCounts: Equatable {
    let created: Int
    let updated: Int
    let archived: Int
    let deleted: Int
    let reused: Int

    init(
        created: Int = 0,
        updated: Int = 0,
        archived: Int = 0,
        deleted: Int = 0,
        reused: Int = 0
    ) {
        self.created = created
        self.updated = updated
        self.archived = archived
        self.deleted = deleted
        self.reused = reused
    }

    init(operations: [AITaskWorkspaceOperation]) {
        var created = 0
        var updated = 0
        var archived = 0
        var deleted = 0
        var reused = 0
        for operation in operations {
            switch operation {
            case .createCategory, .createTask, .createChecklistItem:
                created += 1
            case .updateCategory, .updateTask, .updateChecklistItem:
                updated += 1
            case .archiveTask:
                archived += 1
            case .deleteCategory, .deleteChecklistItem:
                deleted += 1
            case .useExistingCategory:
                reused += 1
            }
        }
        self.init(
            created: created,
            updated: updated,
            archived: archived,
            deleted: deleted,
            reused: reused
        )
    }
}

extension AITaskWorkspaceReviewDraft {
    var mutationCount: Int {
        plan.operations.filter(\.isMutation).count
    }

    var hasDestructiveOperations: Bool {
        plan.operations.contains(where: \.isDestructive)
    }

    var localizedOperationSummary: String {
        AITaskWorkspaceOperationCounts(operations: plan.operations)
            .localizedSummary
    }
}

extension AITaskWorkspaceOperationCounts {
    var localizedSummary: String {
        String.localizedStringWithFormat(
            AppStrings.localized("aiTaskPlan.changes.summaryFormat"),
            Int64(created),
            Int64(updated),
            Int64(archived),
            Int64(deleted),
            Int64(reused)
        )
    }
}

extension AITaskWorkspaceOperation {
    var localizedKind: String {
        let key = switch self {
        case .useExistingCategory:
            "aiTaskPlan.operation.reuse"
        case .createCategory, .createTask, .createChecklistItem:
            "aiTaskPlan.operation.create"
        case .updateCategory, .updateTask, .updateChecklistItem:
            "aiTaskPlan.operation.update"
        case .archiveTask:
            "aiTaskPlan.operation.archive"
        case .deleteCategory, .deleteChecklistItem:
            "aiTaskPlan.operation.delete"
        }
        return AppStrings.localized(key)
    }

    var isMutation: Bool {
        if case .useExistingCategory = self {
            return false
        }
        return true
    }

    var isDestructive: Bool {
        switch self {
        case .deleteCategory, .archiveTask, .deleteChecklistItem:
            true
        case let .updateTask(before, after):
            before.quantityGoal != nil && after.quantityGoal == nil
        case .useExistingCategory,
             .createCategory,
             .updateCategory,
             .createTask,
             .createChecklistItem,
             .updateChecklistItem:
            false
        }
    }

    var presentationIdentitySeed:
        AITaskWorkspaceOperationPresentation.IdentitySeed
    {
        let kind: AITaskWorkspaceOperationPresentation.Kind
        let entityID: UUID
        switch self {
        case let .useExistingCategory(categoryID):
            kind = .reuseCategory
            entityID = categoryID
        case let .createCategory(category):
            kind = .createCategory
            entityID = category.id
        case let .updateCategory(before, _):
            kind = .updateCategory
            entityID = before.id
        case let .deleteCategory(category, _):
            kind = .deleteCategory
            entityID = category.id
        case let .createTask(task):
            kind = .createTask
            entityID = task.id
        case let .updateTask(before, _):
            kind = .updateTask
            entityID = before.id
        case let .archiveTask(before, _, _):
            kind = .archiveTask
            entityID = before.id
        case let .createChecklistItem(item):
            kind = .createChecklistItem
            entityID = item.id
        case let .updateChecklistItem(before, _):
            kind = .updateChecklistItem
            entityID = before.id
        case let .deleteChecklistItem(item):
            kind = .deleteChecklistItem
            entityID = item.id
        }
        return AITaskWorkspaceOperationPresentation.IdentitySeed(
            kind: kind,
            entityID: entityID
        )
    }

    func previewTitle(
        original _: AITaskWorkspaceSnapshot,
        resulting: AITaskWorkspaceSnapshot
    ) -> String {
        switch self {
        case let .useExistingCategory(categoryID):
            resulting.categories.first {
                $0.id == categoryID
            }?.title ?? AppStrings.localized(
                "aiTaskPlan.diff.value.unavailable"
            )
        case let .createCategory(category):
            category.title
        case let .updateCategory(_, after):
            after.title
        case let .deleteCategory(category, _):
            category.title
        case let .createTask(task):
            task.path
        case let .updateTask(_, after):
            after.path
        case let .archiveTask(before, _, _):
            before.path
        case let .createChecklistItem(item):
            item.title
        case let .updateChecklistItem(_, after):
            after.title
        case let .deleteChecklistItem(item):
            item.title
        }
    }

    func previewContext(
        original: AITaskWorkspaceSnapshot,
        resulting: AITaskWorkspaceSnapshot
    ) -> String {
        switch self {
        case let .useExistingCategory(categoryID):
            let title = resulting.categories.first {
                $0.id == categoryID
            }?.title ?? AppStrings.localized(
                "aiTaskPlan.diff.value.unavailable"
            )
            return String.localizedStringWithFormat(
                AppStrings.localized(
                    "aiTaskPlan.operation.reuseCategoryFormat"
                ),
                title
            )
        case .createCategory:
            return AppStrings.localized(
                "aiTaskPlan.operation.categoryCreated"
            )
        case .updateCategory:
            return ""
        case let .deleteCategory(_, affectedRootTaskIDs):
            return String.localizedStringWithFormat(
                AppStrings.localized(
                    "aiTaskPlan.operation.categoryDeleteImpactFormat"
                ),
                Int64(affectedRootTaskIDs.count)
            )
        case let .createTask(task):
            return taskContext(task, snapshot: resulting)
        case let .updateTask(_, after):
            return taskContext(after, snapshot: resulting)
        case let .archiveTask(_, _, affectedDescendantIDs):
            return String.localizedStringWithFormat(
                AppStrings.localized(
                    "aiTaskPlan.operation.archiveImpactFormat"
                ),
                Int64(affectedDescendantIDs.count)
            )
        case let .createChecklistItem(item):
            return checklistContext(item, snapshot: resulting)
        case let .updateChecklistItem(_, after):
            return checklistContext(after, snapshot: resulting)
        case let .deleteChecklistItem(item):
            return checklistContext(item, snapshot: original)
        }
    }

    func fieldChanges(
        original: AITaskWorkspaceSnapshot,
        resulting: AITaskWorkspaceSnapshot
    ) -> [AITaskWorkspaceFieldChange] {
        var changes: [AITaskWorkspaceFieldChange] = []
        switch self {
        case let .updateCategory(before, after):
            changes.append(
                field: .title,
                before: .text(before.title),
                after: .text(after.title)
            )
            changes.append(
                field: .icon,
                before: .icon(before.iconName),
                after: .icon(after.iconName)
            )
            changes.append(
                field: .color,
                before: .color(before.colorHex),
                after: .color(after.colorHex)
            )
            changes.append(
                field: .forecast,
                before: .boolean(before.includesInForecast),
                after: .boolean(after.includesInForecast)
            )
        case let .updateTask(before, after):
            changes.append(
                field: .title,
                before: .text(before.title),
                after: .text(after.title)
            )
            if before.parentID != after.parentID || before.path != after.path {
                changes.append(
                    AITaskWorkspaceFieldChange(
                        field: .path,
                        before: .text(before.path),
                        after: .text(after.path)
                    )
                )
            }
            if before.categoryID != after.categoryID {
                changes.append(
                    AITaskWorkspaceFieldChange(
                        field: .category,
                        before: categoryValue(
                            id: before.categoryID,
                            snapshot: original
                        ),
                        after: categoryValue(
                            id: after.categoryID,
                            snapshot: resulting
                        )
                    )
                )
            }
            changes.append(
                field: .notes,
                before: .text(before.notes),
                after: .text(after.notes)
            )
            changes.append(
                field: .estimatedTime,
                before: .minutes(before.estimatedMinutes),
                after: .minutes(after.estimatedMinutes)
            )
            changes.append(
                field: .dueDate,
                before: .date(before.dueAt),
                after: .date(after.dueAt)
            )
            changes.append(
                field: .icon,
                before: .icon(before.iconName),
                after: .icon(after.iconName)
            )
            changes.append(
                field: .color,
                before: .color(before.colorHex),
                after: .color(after.colorHex)
            )
            changes.append(
                field: .quantityGoal,
                before: .quantityGoal(before.quantityGoal),
                after: .quantityGoal(after.quantityGoal)
            )
            changes.append(
                field: .recurrence,
                before: .recurrence(before.dailyRecurrence),
                after: .recurrence(after.dailyRecurrence)
            )
        case let .updateChecklistItem(before, after):
            changes.append(
                field: .title,
                before: .text(before.title),
                after: .text(after.title)
            )
            changes.append(
                field: .completion,
                before: .boolean(before.isCompleted),
                after: .boolean(after.isCompleted)
            )
            changes.append(
                field: .icon,
                before: .icon(before.iconName),
                after: .icon(after.iconName)
            )
            changes.append(
                field: .color,
                before: .color(before.colorHex),
                after: .color(after.colorHex)
            )
        case .useExistingCategory,
             .createCategory,
             .deleteCategory,
             .createTask,
             .archiveTask,
             .createChecklistItem,
             .deleteChecklistItem:
            break
        }
        return changes
    }

    private func taskContext(
        _ task: AITaskWorkspaceTask,
        snapshot: AITaskWorkspaceSnapshot
    ) -> String {
        if let categoryID = task.categoryID,
           let category = snapshot.categories.first(where: {
               $0.id == categoryID
           })
        {
            return String.localizedStringWithFormat(
                AppStrings.localized(
                    "aiTaskPlan.operation.taskCategoryFormat"
                ),
                category.title
            )
        }
        return AppStrings.localized("aiTaskPlan.uncategorized")
    }

    private func checklistContext(
        _ item: AITaskWorkspaceChecklistItem,
        snapshot: AITaskWorkspaceSnapshot
    ) -> String {
        let path = snapshot.tasks.first {
            $0.id == item.taskID
        }?.path ?? AppStrings.localized(
            "aiTaskPlan.diff.value.unavailable"
        )
        return String.localizedStringWithFormat(
            AppStrings.localized(
                "aiTaskPlan.operation.checklistTaskFormat"
            ),
            path
        )
    }

    private func categoryValue(
        id: UUID?,
        snapshot: AITaskWorkspaceSnapshot
    ) -> AITaskWorkspacePreviewValue {
        guard let id else { return .optionalText(nil) }
        let title = snapshot.categories.first { $0.id == id }?.title ??
            AppStrings.localized("aiTaskPlan.diff.value.unavailable")
        return .optionalText(title)
    }
}

private extension [AITaskWorkspaceFieldChange] {
    mutating func append(
        field: AITaskWorkspacePreviewField,
        before: AITaskWorkspacePreviewValue,
        after: AITaskWorkspacePreviewValue
    ) {
        guard before != after else { return }
        append(
            AITaskWorkspaceFieldChange(
                field: field,
                before: before,
                after: after
            )
        )
    }
}
