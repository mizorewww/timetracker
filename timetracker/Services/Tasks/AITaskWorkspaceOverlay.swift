import Foundation

nonisolated enum AITaskWorkspaceOverlayError: Error, Equatable, Sendable {
    case identityConflict(UUID)
    case categoryUnavailable(UUID)
    case categoryNameUnavailable(String)
    case categoryAlreadyExists(UUID)
    case ambiguousCategoryName(categoryIDs: [UUID])
    case taskUnavailable(UUID)
    case checklistItemUnavailable(UUID)
    case taskArchived(UUID)
    case childTaskCannotHaveCategory
    case hierarchyCycle
    case depthExceeded
    case invalidEstimate(Int)
    case invalidSortOrder
    case invalidDueDate
}

nonisolated enum AITaskWorkspaceOperation: Equatable, Sendable {
    case useExistingCategory(categoryID: UUID)
    case createCategory(AITaskWorkspaceCategory)
    case updateCategory(
        before: AITaskWorkspaceCategory,
        after: AITaskWorkspaceCategory
    )
    case deleteCategory(
        category: AITaskWorkspaceCategory,
        affectedRootTaskIDs: [UUID]
    )
    case createTask(AITaskWorkspaceTask)
    case updateTask(
        before: AITaskWorkspaceTask,
        after: AITaskWorkspaceTask
    )
    case archiveTask(
        before: AITaskWorkspaceTask,
        after: AITaskWorkspaceTask,
        affectedDescendantIDs: [UUID]
    )
    case createChecklistItem(AITaskWorkspaceChecklistItem)
    case updateChecklistItem(
        before: AITaskWorkspaceChecklistItem,
        after: AITaskWorkspaceChecklistItem
    )
    case deleteChecklistItem(AITaskWorkspaceChecklistItem)
}

/// A provider-session workspace. CRUD calls mutate only this in-memory value;
/// durable writes are intentionally left to a later preview/confirmation and
/// store-scoped coordinator boundary.
nonisolated struct AITaskWorkspaceOverlay: Equatable, Sendable {
    private(set) var snapshot: AITaskWorkspaceSnapshot
    private(set) var operations: [AITaskWorkspaceOperation] = []

    init(snapshot: AITaskWorkspaceSnapshot) {
        self.snapshot = AITaskWorkspaceSnapshot(
            schemaVersion: snapshot.schemaVersion,
            categories: snapshot.categories,
            tasks: snapshot.tasks,
            checklistItems: snapshot.checklistItems
        )
    }

    func category(id: UUID) -> AITaskWorkspaceCategory? {
        snapshot.categories.first { $0.id == id }
    }

    func task(id: UUID) -> AITaskWorkspaceTask? {
        snapshot.tasks.first { $0.id == id }
    }

    func checklistItem(id: UUID) -> AITaskWorkspaceChecklistItem? {
        snapshot.checklistItems.first { $0.id == id }
    }

    func checklistItems(taskID: UUID) -> [AITaskWorkspaceChecklistItem] {
        snapshot.checklistItems.filter { $0.taskID == taskID }
    }

    @discardableResult
    mutating func useExistingCategory(
        named title: String
    ) throws -> AITaskWorkspaceCategory {
        let prepared = try TaskPersistencePolicy.prepareCategory(
            title: title,
            colorHex: nil,
            iconName: nil
        )
        let matches = categories(named: prepared.title)
        guard !matches.isEmpty else {
            throw AITaskWorkspaceOverlayError.categoryNameUnavailable(
                prepared.title
            )
        }
        guard matches.count == 1, let category = matches.first else {
            throw ambiguousCategoryError(matches)
        }
        operations.append(.useExistingCategory(categoryID: category.id))
        return category
    }

    @discardableResult
    mutating func createCategory(
        id: UUID,
        title: String,
        iconName: String,
        colorHex: String,
        includesInForecast: Bool = true,
        sortOrder: Double? = nil
    ) throws -> AITaskWorkspaceCategory {
        try requireUnusedIdentity(id)
        let prepared = try TaskPersistencePolicy.prepareCategory(
            title: title,
            colorHex: colorHex,
            iconName: iconName
        )
        try requireCategoryNameAvailable(prepared.title, excluding: nil)
        let resolvedSortOrder = try preparedSortOrder(
            sortOrder,
            fallback: nextCategorySortOrder
        )
        let category = AITaskWorkspaceCategory(
            id: id,
            title: prepared.title,
            iconName: ChecklistVisualSanitizer.sanitizedIcon(
                prepared.iconName
            ),
            colorHex: ChecklistVisualSanitizer.sanitizedColor(
                prepared.colorHex
            ),
            includesInForecast: includesInForecast,
            sortOrder: resolvedSortOrder
        )
        replaceSnapshot(categories: snapshot.categories + [category])
        let canonical = self.category(id: id)!
        operations.append(.createCategory(canonical))
        return canonical
    }

    @discardableResult
    mutating func updateCategory(
        id: UUID,
        title: String,
        iconName: String,
        colorHex: String,
        includesInForecast: Bool
    ) throws -> AITaskWorkspaceCategory {
        guard let before = category(id: id) else {
            throw AITaskWorkspaceOverlayError.categoryUnavailable(id)
        }
        let prepared = try TaskPersistencePolicy.prepareCategory(
            title: title,
            colorHex: colorHex,
            iconName: iconName
        )
        if prepared.title != before.title {
            try requireCategoryNameAvailable(prepared.title, excluding: id)
        }
        var proposed = before
        proposed.title = prepared.title
        proposed.iconName = ChecklistVisualSanitizer.sanitizedIcon(
            prepared.iconName
        )
        proposed.colorHex = ChecklistVisualSanitizer.sanitizedColor(
            prepared.colorHex
        )
        proposed.includesInForecast = includesInForecast
        guard proposed != before else { return before }

        replaceSnapshot(
            categories: replacing(snapshot.categories, id: id, with: proposed)
        )
        let after = category(id: id)!
        operations.append(.updateCategory(before: before, after: after))
        return after
    }

    @discardableResult
    mutating func deleteCategory(
        id: UUID
    ) throws -> AITaskWorkspaceCategory {
        guard let deleted = category(id: id) else {
            throw AITaskWorkspaceOverlayError.categoryUnavailable(id)
        }
        let affectedTaskIDs = snapshot.tasks
            .filter { $0.parentID == nil && $0.categoryID == id }
            .map(\.id)
            .sorted(by: Self.uuidOrder)
        let updatedTasks = snapshot.tasks.map { task -> AITaskWorkspaceTask in
            guard task.categoryID == id else { return task }
            var updated = task
            updated.categoryID = nil
            return updated
        }
        replaceSnapshot(
            categories: snapshot.categories.filter { $0.id != id },
            tasks: updatedTasks
        )
        operations.append(
            .deleteCategory(
                category: deleted,
                affectedRootTaskIDs: affectedTaskIDs
            )
        )
        return deleted
    }

    @discardableResult
    mutating func createTask(
        id: UUID,
        title: String,
        parentID: UUID?,
        categoryID: UUID?,
        notes: String,
        estimatedMinutes: Int?,
        dueAt: Date?,
        iconName: String,
        colorHex: String,
        quantityGoal: TaskQuantityGoalDraft? = nil,
        dailyRecurrence: TaskDailyRecurrenceDraft? = nil,
        sortOrder: Double? = nil
    ) throws -> AITaskWorkspaceTask {
        try requireUnusedIdentity(id)
        try validateTaskPlacement(
            taskID: id,
            parentID: parentID,
            categoryID: categoryID
        )
        let prepared = try preparedTaskValues(
            title: title,
            notes: notes,
            estimatedMinutes: estimatedMinutes,
            dueAt: dueAt,
            iconName: iconName,
            colorHex: colorHex,
            quantityGoal: quantityGoal,
            dailyRecurrence: dailyRecurrence
        )
        let resolvedSortOrder = try preparedSortOrder(
            sortOrder,
            fallback: nextTaskSortOrder(parentID: parentID)
        )
        let task = AITaskWorkspaceTask(
            id: id,
            title: prepared.title,
            parentID: parentID,
            categoryID: categoryID,
            path: prepared.title,
            notes: prepared.notes,
            estimatedMinutes: estimatedMinutes,
            dueAt: dueAt,
            iconName: prepared.iconName,
            colorHex: prepared.colorHex,
            sortOrder: resolvedSortOrder,
            isArchived: false,
            quantityGoal: prepared.quantityGoal,
            dailyRecurrence: prepared.dailyRecurrence
        )
        replaceSnapshot(tasks: snapshot.tasks + [task])
        let canonical = self.task(id: id)!
        operations.append(.createTask(canonical))
        return canonical
    }

    @discardableResult
    mutating func updateTask(
        id: UUID,
        title: String,
        parentID: UUID?,
        categoryID: UUID?,
        notes: String,
        estimatedMinutes: Int?,
        dueAt: Date?,
        iconName: String,
        colorHex: String,
        quantityGoal: TaskQuantityGoalDraft? = nil,
        dailyRecurrence: TaskDailyRecurrenceDraft? = nil
    ) throws -> AITaskWorkspaceTask {
        guard let before = task(id: id) else {
            throw AITaskWorkspaceOverlayError.taskUnavailable(id)
        }
        guard !before.isArchived, isTaskAvailable(id) else {
            throw AITaskWorkspaceOverlayError.taskArchived(id)
        }
        if before.dailyRecurrence != nil, dailyRecurrence == nil {
            throw TaskProgressDraftMutationError
                .existingRecurrenceMustBePreserved
        }
        try validateTaskPlacement(
            taskID: id,
            parentID: parentID,
            categoryID: categoryID
        )
        let prepared = try preparedTaskValues(
            title: title,
            notes: notes,
            estimatedMinutes: estimatedMinutes,
            dueAt: dueAt,
            iconName: iconName,
            colorHex: colorHex,
            quantityGoal: quantityGoal,
            dailyRecurrence: dailyRecurrence
        )
        var proposed = before
        proposed.title = prepared.title
        proposed.parentID = parentID
        proposed.categoryID = categoryID
        proposed.notes = prepared.notes
        proposed.estimatedMinutes = estimatedMinutes
        proposed.dueAt = dueAt
        proposed.iconName = prepared.iconName
        proposed.colorHex = prepared.colorHex
        proposed.quantityGoal = prepared.quantityGoal
        proposed.dailyRecurrence = prepared.dailyRecurrence
        guard proposed != before else { return before }

        replaceSnapshot(
            tasks: replacing(snapshot.tasks, id: id, with: proposed)
        )
        let after = task(id: id)!
        operations.append(.updateTask(before: before, after: after))
        return after
    }

    /// Product-facing task deletion is archive-only. The task and its stable ID
    /// remain readable in the overlay so preview and conflict validation can
    /// describe the affected branch.
    @discardableResult
    mutating func deleteTask(id: UUID) throws -> AITaskWorkspaceTask {
        guard let before = task(id: id) else {
            throw AITaskWorkspaceOverlayError.taskUnavailable(id)
        }
        guard !before.isArchived else { return before }

        var proposed = before
        proposed.isArchived = true
        let affectedDescendantIDs = descendantIDs(of: id)
            .sorted(by: Self.uuidOrder)
        replaceSnapshot(
            tasks: replacing(snapshot.tasks, id: id, with: proposed)
        )
        let after = task(id: id)!
        operations.append(
            .archiveTask(
                before: before,
                after: after,
                affectedDescendantIDs: affectedDescendantIDs
            )
        )
        return after
    }

    @discardableResult
    mutating func createChecklistItem(
        id: UUID,
        taskID: UUID,
        title: String,
        isCompleted: Bool,
        iconName: String,
        colorHex: String,
        sortOrder: Double? = nil
    ) throws -> AITaskWorkspaceChecklistItem {
        try requireUnusedIdentity(id)
        try requireAvailableTask(taskID)
        let prepared = try preparedChecklistItem(
            title: title,
            isCompleted: isCompleted,
            iconName: iconName,
            colorHex: colorHex
        )
        let resolvedSortOrder = try preparedSortOrder(
            sortOrder,
            fallback: nextChecklistSortOrder(taskID: taskID)
        )
        let item = AITaskWorkspaceChecklistItem(
            id: id,
            taskID: taskID,
            title: prepared.title,
            isCompleted: prepared.isCompleted,
            iconName: prepared.iconName,
            colorHex: prepared.colorHex,
            sortOrder: resolvedSortOrder
        )
        replaceSnapshot(checklistItems: snapshot.checklistItems + [item])
        let canonical = checklistItem(id: id)!
        operations.append(.createChecklistItem(canonical))
        return canonical
    }

    @discardableResult
    mutating func updateChecklistItem(
        id: UUID,
        title: String,
        isCompleted: Bool,
        iconName: String,
        colorHex: String
    ) throws -> AITaskWorkspaceChecklistItem {
        guard let before = checklistItem(id: id) else {
            throw AITaskWorkspaceOverlayError.checklistItemUnavailable(id)
        }
        try requireAvailableTask(before.taskID)
        let prepared = try preparedChecklistItem(
            title: title,
            isCompleted: isCompleted,
            iconName: iconName,
            colorHex: colorHex
        )
        var proposed = before
        proposed.title = prepared.title
        proposed.isCompleted = prepared.isCompleted
        proposed.iconName = prepared.iconName
        proposed.colorHex = prepared.colorHex
        guard proposed != before else { return before }

        replaceSnapshot(
            checklistItems: replacing(
                snapshot.checklistItems,
                id: id,
                with: proposed
            )
        )
        let after = checklistItem(id: id)!
        operations.append(.updateChecklistItem(before: before, after: after))
        return after
    }

    @discardableResult
    mutating func deleteChecklistItem(
        id: UUID
    ) throws -> AITaskWorkspaceChecklistItem {
        guard let deleted = checklistItem(id: id) else {
            throw AITaskWorkspaceOverlayError.checklistItemUnavailable(id)
        }
        try requireAvailableTask(deleted.taskID)
        replaceSnapshot(
            checklistItems: snapshot.checklistItems.filter { $0.id != id }
        )
        operations.append(.deleteChecklistItem(deleted))
        return deleted
    }
}

private nonisolated extension AITaskWorkspaceOverlay {
    struct PreparedTaskValues {
        let title: String
        let notes: String
        let iconName: String
        let colorHex: String
        let quantityGoal: TaskQuantityGoalDraft?
        let dailyRecurrence: TaskDailyRecurrenceDraft?
    }

    static let categoryNameLocale = Locale(identifier: "en_US_POSIX")

    var nextCategorySortOrder: Double {
        (snapshot.categories.map(\.sortOrder).max() ?? 0) + 10
    }

    func nextTaskSortOrder(parentID: UUID?) -> Double {
        (
            snapshot.tasks
                .filter { $0.parentID == parentID }
                .map(\.sortOrder)
                .max() ?? 0
        ) + 10
    }

    func nextChecklistSortOrder(taskID: UUID) -> Double {
        (
            snapshot.checklistItems
                .filter { $0.taskID == taskID }
                .map(\.sortOrder)
                .max() ?? 0
        ) + 10
    }

    func categories(named title: String) -> [AITaskWorkspaceCategory] {
        let key = Self.normalizedCategoryName(title)
        return snapshot.categories
            .filter { Self.normalizedCategoryName($0.title) == key }
            .sorted { $0.id.uuidString < $1.id.uuidString }
    }

    func ambiguousCategoryError(
        _ categories: [AITaskWorkspaceCategory]
    ) -> AITaskWorkspaceOverlayError {
        .ambiguousCategoryName(
            categoryIDs: categories.map(\.id).sorted(by: Self.uuidOrder)
        )
    }

    func requireCategoryNameAvailable(
        _ title: String,
        excluding excludedID: UUID?
    ) throws {
        let matches = categories(named: title).filter { $0.id != excludedID }
        if matches.count == 1, let existing = matches.first {
            throw AITaskWorkspaceOverlayError.categoryAlreadyExists(existing.id)
        }
        if matches.count > 1 {
            throw ambiguousCategoryError(matches)
        }
    }

    func requireUnusedIdentity(_ id: UUID) throws {
        let isUsed = snapshot.categories.contains { $0.id == id } ||
            snapshot.tasks.contains { $0.id == id } ||
            snapshot.checklistItems.contains { $0.id == id }
        guard !isUsed else {
            throw AITaskWorkspaceOverlayError.identityConflict(id)
        }
    }

    func validateTaskPlacement(
        taskID: UUID,
        parentID: UUID?,
        categoryID: UUID?
    ) throws {
        if parentID != nil, categoryID != nil {
            throw AITaskWorkspaceOverlayError.childTaskCannotHaveCategory
        }
        if let categoryID, category(id: categoryID) == nil {
            throw AITaskWorkspaceOverlayError.categoryUnavailable(categoryID)
        }
        if let parentID {
            guard task(id: parentID) != nil else {
                throw AITaskWorkspaceOverlayError.taskUnavailable(parentID)
            }
            try requireAvailableTask(parentID)
            if parentID == taskID || descendantIDs(of: taskID).contains(parentID) {
                throw AITaskWorkspaceOverlayError.hierarchyCycle
            }
        }
        try validateMaximumTaskDepth(
            taskID: taskID,
            parentID: parentID
        )
    }

    func validateMaximumTaskDepth(
        taskID: UUID,
        parentID: UUID?
    ) throws {
        var parentByTaskID = snapshot.tasks.reduce(
            into: [UUID: UUID]()
        ) { result, task in
            if let parentID = task.parentID {
                result[task.id] = parentID
            }
        }
        if let parentID {
            parentByTaskID[taskID] = parentID
        } else {
            parentByTaskID.removeValue(forKey: taskID)
        }

        let affectedTaskIDs = [taskID] + descendantIDs(of: taskID)
        for affectedTaskID in affectedTaskIDs {
            var depth = 0
            var visited: Set<UUID> = [affectedTaskID]
            var cursor = affectedTaskID
            while let parentID = parentByTaskID[cursor] {
                guard visited.insert(parentID).inserted else {
                    throw AITaskWorkspaceOverlayError.hierarchyCycle
                }
                depth += 1
                guard depth <= 6 else {
                    throw AITaskWorkspaceOverlayError.depthExceeded
                }
                cursor = parentID
            }
        }
    }

    func requireAvailableTask(_ taskID: UUID) throws {
        guard task(id: taskID) != nil else {
            throw AITaskWorkspaceOverlayError.taskUnavailable(taskID)
        }
        guard isTaskAvailable(taskID) else {
            throw AITaskWorkspaceOverlayError.taskArchived(taskID)
        }
    }

    func isTaskAvailable(_ taskID: UUID) -> Bool {
        let taskByID = snapshot.tasks.reduce(
            into: [UUID: AITaskWorkspaceTask]()
        ) {
            $0[$1.id] = $1
        }
        var visited = Set<UUID>()
        var cursor = taskByID[taskID]
        while let current = cursor {
            guard visited.insert(current.id).inserted,
                  !current.isArchived
            else {
                return false
            }
            cursor = current.parentID.flatMap { taskByID[$0] }
        }
        return true
    }

    func descendantIDs(of taskID: UUID) -> [UUID] {
        let childrenByParentID = Dictionary(
            grouping: snapshot.tasks,
            by: \.parentID
        )
        var result: [UUID] = []
        var pending = (childrenByParentID[taskID] ?? []).map(\.id)
        var visited = Set<UUID>()
        while let currentID = pending.popLast() {
            guard currentID != taskID, visited.insert(currentID).inserted else {
                continue
            }
            result.append(currentID)
            pending.append(
                contentsOf: (childrenByParentID[currentID] ?? []).map(\.id)
            )
        }
        return result
    }

    func preparedTaskValues(
        title: String,
        notes: String,
        estimatedMinutes: Int?,
        dueAt: Date?,
        iconName: String,
        colorHex: String,
        quantityGoal: TaskQuantityGoalDraft?,
        dailyRecurrence: TaskDailyRecurrenceDraft?
    ) throws -> PreparedTaskValues {
        if let estimatedMinutes,
           !TaskEstimatePolicy.minuteRange.contains(estimatedMinutes)
        {
            throw AITaskWorkspaceOverlayError.invalidEstimate(estimatedMinutes)
        }
        if let dueAt, !dueAt.timeIntervalSinceReferenceDate.isFinite {
            throw AITaskWorkspaceOverlayError.invalidDueDate
        }
        let prepared = try TaskPersistencePolicy.prepareTask(
            title: title,
            colorHex: colorHex,
            iconName: iconName,
            notes: notes
        )
        let preparedProgress = try TaskProgressDraftPersistencePolicy.prepare(
            quantityGoal: quantityGoal,
            dailyRecurrence: dailyRecurrence
        )
        return PreparedTaskValues(
            title: prepared.title,
            notes: prepared.notes ?? "",
            iconName: ChecklistVisualSanitizer.sanitizedIcon(
                prepared.iconName
            ),
            colorHex: ChecklistVisualSanitizer.sanitizedColor(
                prepared.colorHex
            ),
            quantityGoal: preparedProgress.quantityGoal.map {
                TaskQuantityGoalDraft(
                    targetAmount: $0.targetAmount,
                    unitLabel: $0.unitLabel
                )
            },
            dailyRecurrence: preparedProgress.dailyRecurrence
        )
    }

    func preparedChecklistItem(
        title: String,
        isCompleted: Bool,
        iconName: String,
        colorHex: String
    ) throws -> PreparedChecklistDraft {
        try ChecklistDraftPersistencePolicy.prepare([
            ChecklistEditorDraft(
                title: title,
                isCompleted: isCompleted,
                iconName: iconName,
                colorHex: colorHex
            ),
        ])[0]
    }

    func preparedSortOrder(
        _ requested: Double?,
        fallback: Double
    ) throws -> Double {
        let value = requested ?? fallback
        guard value.isFinite else {
            throw AITaskWorkspaceOverlayError.invalidSortOrder
        }
        return value
    }

    mutating func replaceSnapshot(
        categories: [AITaskWorkspaceCategory]? = nil,
        tasks: [AITaskWorkspaceTask]? = nil,
        checklistItems: [AITaskWorkspaceChecklistItem]? = nil
    ) {
        snapshot = AITaskWorkspaceSnapshot(
            schemaVersion: snapshot.schemaVersion,
            categories: categories ?? snapshot.categories,
            tasks: tasks ?? snapshot.tasks,
            checklistItems: checklistItems ?? snapshot.checklistItems
        )
    }

    func replacing<Element: Identifiable>(
        _ values: [Element],
        id: Element.ID,
        with replacement: Element
    ) -> [Element] where Element.ID: Equatable {
        values.map { $0.id == id ? replacement : $0 }
    }

    static func normalizedCategoryName(_ value: String) -> String {
        value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .folding(
                options: [
                    .caseInsensitive,
                    .diacriticInsensitive,
                    .widthInsensitive,
                ],
                locale: categoryNameLocale
            )
    }

    static func uuidOrder(_ lhs: UUID, _ rhs: UUID) -> Bool {
        lhs.uuidString < rhs.uuidString
    }
}
