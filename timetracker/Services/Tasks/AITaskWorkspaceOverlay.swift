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
    /// The icon or color is outside the catalog offered to the model.
    case invalidVisual
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
    /// Deepest ancestor chain a proposed task may have; matches the number of
    /// path components the task tree displays.
    static let maximumAncestorDepth = TaskTreeService.maximumDisplayedPathComponents

    private(set) var snapshot: AITaskWorkspaceSnapshot {
        didSet { indexes = Indexes(snapshot) }
    }

    private(set) var operations: [AITaskWorkspaceOperation] = []
    private var indexes: Indexes

    init(snapshot: AITaskWorkspaceSnapshot) {
        self.snapshot = snapshot
        indexes = Indexes(snapshot)
    }

    func category(id: UUID) -> AITaskWorkspaceCategory? {
        indexes.categoryByID[id]
    }

    func task(id: UUID) -> AITaskWorkspaceTask? {
        indexes.taskByID[id]
    }

    func checklistItem(id: UUID) -> AITaskWorkspaceChecklistItem? {
        indexes.checklistItemByID[id]
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
        try requireCatalogVisual(iconName: iconName, colorHex: colorHex)
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
            iconName: iconName,
            colorHex: colorHex,
            includesInForecast: includesInForecast,
            sortOrder: resolvedSortOrder
        )
        replaceSnapshot(categories: snapshot.categories + [category])
        operations.append(.createCategory(category))
        return category
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
        try requireCatalogVisual(iconName: iconName, colorHex: colorHex)
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
        proposed.iconName = iconName
        proposed.colorHex = colorHex
        proposed.includesInForecast = includesInForecast
        guard proposed != before else { return before }

        replaceSnapshot(
            categories: replacing(snapshot.categories, id: id, with: proposed)
        )
        operations.append(.updateCategory(before: before, after: proposed))
        return proposed
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
        operations.append(.createTask(task))
        return task
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
        operations.append(.updateTask(before: before, after: proposed))
        return proposed
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
        operations.append(
            .archiveTask(
                before: before,
                after: proposed,
                affectedDescendantIDs: affectedDescendantIDs
            )
        )
        return proposed
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
        operations.append(.createChecklistItem(item))
        return item
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
        operations.append(.updateChecklistItem(before: before, after: proposed))
        return proposed
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
    /// Lookups rebuilt once per snapshot change so validation does not rescan
    /// or regroup the workspace per check.
    struct Indexes: Equatable {
        let categoryByID: [UUID: AITaskWorkspaceCategory]
        let taskByID: [UUID: AITaskWorkspaceTask]
        let checklistItemByID: [UUID: AITaskWorkspaceChecklistItem]
        let childIDsByParentID: [UUID: [UUID]]

        init(_ snapshot: AITaskWorkspaceSnapshot) {
            categoryByID = Dictionary(
                snapshot.categories.map { ($0.id, $0) },
                uniquingKeysWith: { first, _ in first }
            )
            taskByID = Dictionary(
                snapshot.tasks.map { ($0.id, $0) },
                uniquingKeysWith: { first, _ in first }
            )
            checklistItemByID = Dictionary(
                snapshot.checklistItems.map { ($0.id, $0) },
                uniquingKeysWith: { first, _ in first }
            )
            childIDsByParentID = snapshot.tasks.reduce(into: [:]) { result, task in
                if let parentID = task.parentID {
                    result[parentID, default: []].append(task.id)
                }
            }
        }
    }

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
        SortOrderPolicy.after(snapshot.categories.map(\.sortOrder).max())
    }

    func nextTaskSortOrder(parentID: UUID?) -> Double {
        SortOrderPolicy.after(
            snapshot.tasks.filter { $0.parentID == parentID }.map(\.sortOrder).max()
        )
    }

    func nextChecklistSortOrder(taskID: UUID) -> Double {
        SortOrderPolicy.after(
            snapshot.checklistItems.filter { $0.taskID == taskID }.map(\.sortOrder).max()
        )
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

    func requireCatalogVisual(iconName: String, colorHex: String) throws {
        guard SymbolCatalog.symbolNameSet.contains(iconName),
              TaskColorPalette.hexValues.contains(colorHex)
        else {
            throw AITaskWorkspaceOverlayError.invalidVisual
        }
    }

    func requireUnusedIdentity(_ id: UUID) throws {
        let isUsed = indexes.categoryByID[id] != nil ||
            indexes.taskByID[id] != nil ||
            indexes.checklistItemByID[id] != nil
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

    /// The moved task's new depth plus the height of its subtree must fit
    /// within `maximumAncestorDepth`.
    func validateMaximumTaskDepth(
        taskID: UUID,
        parentID: UUID?
    ) throws {
        var depth = 0
        var visited: Set<UUID> = [taskID]
        var cursor = parentID
        while let current = cursor {
            guard visited.insert(current).inserted else {
                throw AITaskWorkspaceOverlayError.hierarchyCycle
            }
            depth += 1
            cursor = indexes.taskByID[current]?.parentID
        }

        var level = indexes.childIDsByParentID[taskID] ?? []
        while !level.isEmpty {
            depth += 1
            level = level
                .filter { visited.insert($0).inserted }
                .flatMap { indexes.childIDsByParentID[$0] ?? [] }
        }
        guard depth <= Self.maximumAncestorDepth else {
            throw AITaskWorkspaceOverlayError.depthExceeded
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
        let taskByID = indexes.taskByID
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
        var result: [UUID] = []
        var pending = indexes.childIDsByParentID[taskID] ?? []
        var visited = Set<UUID>()
        while let currentID = pending.popLast() {
            guard currentID != taskID, visited.insert(currentID).inserted else {
                continue
            }
            result.append(currentID)
            pending.append(contentsOf: indexes.childIDsByParentID[currentID] ?? [])
        }
        return result
    }

    func preparedTaskValues(
        title: String,
        notes: String,
        estimatedMinutes: Int?,
        dueAt _: Date?,
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
        try requireCatalogVisual(iconName: iconName, colorHex: colorHex)
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
            iconName: iconName,
            colorHex: colorHex,
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
        try requireCatalogVisual(iconName: iconName, colorHex: colorHex)
        return try ChecklistDraftPersistencePolicy.prepare([
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
