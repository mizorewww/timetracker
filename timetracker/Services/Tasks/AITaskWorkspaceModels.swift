import CryptoKit
import Foundation

nonisolated struct AITaskWorkspaceCategory:
    Codable,
    Equatable,
    Identifiable,
    Sendable
{
    let id: UUID
    var title: String
    var iconName: String
    var colorHex: String
    var includesInForecast: Bool
    var sortOrder: Double
}

nonisolated struct AITaskWorkspaceTask:
    Codable,
    Equatable,
    Identifiable,
    Sendable
{
    let id: UUID
    var title: String
    var parentID: UUID?
    var categoryID: UUID?
    var path: String
    var notes: String
    var estimatedMinutes: Int?
    var dueAt: Date?
    var iconName: String
    var colorHex: String
    var sortOrder: Double
    var isArchived: Bool
    var quantityGoal: TaskQuantityGoalDraft? = nil
    var dailyRecurrence: TaskDailyRecurrenceDraft? = nil
}

nonisolated struct AITaskWorkspaceChecklistItem:
    Codable,
    Equatable,
    Identifiable,
    Sendable
{
    let id: UUID
    let taskID: UUID
    var title: String
    var isCompleted: Bool
    var iconName: String
    var colorHex: String
    var sortOrder: Double
}

/// The complete, provider-facing task workspace. Arrays are canonically sorted
/// and task paths are always rebuilt from every available ancestor. No item
/// count or path-depth window is applied here.
nonisolated struct AITaskWorkspaceSnapshot: Codable, Equatable, Sendable {
    static let currentSchemaVersion = 1

    let schemaVersion: Int
    let categories: [AITaskWorkspaceCategory]
    let tasks: [AITaskWorkspaceTask]
    let checklistItems: [AITaskWorkspaceChecklistItem]
    var contextFingerprint: String {
        Self.contextFingerprint(
            schemaVersion: schemaVersion,
            categories: categories,
            tasks: tasks,
            checklistItems: checklistItems
        )
    }

    init(
        schemaVersion: Int = currentSchemaVersion,
        categories: [AITaskWorkspaceCategory],
        tasks: [AITaskWorkspaceTask],
        checklistItems: [AITaskWorkspaceChecklistItem]
    ) {
        self.schemaVersion = schemaVersion
        self.categories = Self.canonicalCategories(categories)
        self.tasks = Self.canonicalTasks(tasks)
        self.checklistItems = Self.canonicalChecklistItems(
            checklistItems,
            tasks: self.tasks
        )
    }

    private enum CodingKeys: String, CodingKey {
        case schemaVersion
        case categories
        case tasks
        case checklistItems
        case contextFingerprint
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let transmittedFingerprint = try container.decode(
            String.self,
            forKey: .contextFingerprint
        )
        try self.init(
            schemaVersion: container.decode(Int.self, forKey: .schemaVersion),
            categories: container.decode(
                [AITaskWorkspaceCategory].self,
                forKey: .categories
            ),
            tasks: container.decode(
                [AITaskWorkspaceTask].self,
                forKey: .tasks
            ),
            checklistItems: container.decode(
                [AITaskWorkspaceChecklistItem].self,
                forKey: .checklistItems
            )
        )
        guard transmittedFingerprint == contextFingerprint else {
            throw DecodingError.dataCorruptedError(
                forKey: .contextFingerprint,
                in: container,
                debugDescription:
                "The task workspace context fingerprint does not match its facts."
            )
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(schemaVersion, forKey: .schemaVersion)
        try container.encode(categories, forKey: .categories)
        try container.encode(tasks, forKey: .tasks)
        try container.encode(checklistItems, forKey: .checklistItems)
        try container.encode(
            contextFingerprint,
            forKey: .contextFingerprint
        )
    }
}

nonisolated struct AITaskWorkspaceMutationBaselines: Equatable, Sendable {
    let categoryMutationIDs: [UUID: UUID]
    let taskMutationIDs: [UUID: UUID]
    let categoryAssignmentMutationIDsByTaskID: [UUID: UUID]
    let checklistItemMutationIDs: [UUID: UUID]
    let checklistVisualMutationIDsByItemID: [UUID: UUID]
}

/// Keeps optimistic-concurrency revisions beside, but deliberately outside,
/// the Codable provider-facing snapshot. Tool adapters and models never choose
/// or rewrite these baselines.
nonisolated struct AITaskWorkspaceCapture: Equatable, Sendable {
    let snapshot: AITaskWorkspaceSnapshot
    let baselines: AITaskWorkspaceMutationBaselines

    @MainActor
    init(
        taskCategories: [TaskCategory],
        tasks: [TaskNode],
        taskCategoryAssignments: [TaskCategoryAssignment],
        checklistItems: [ChecklistItem],
        checklistVisuals: [ChecklistItemVisual],
        quantityGoals: [TaskQuantityGoal] = [],
        recurrenceRules: [TaskRecurrenceRule] = []
    ) {
        let canonicalCategories = taskCategories.visibleDeduplicatedByID()
        let canonicalTasks = tasks.visibleDeduplicatedByID()
        let categoryIDs = Set(canonicalCategories.map(\.id))
        let taskIDs = Set(canonicalTasks.map(\.id))
        let repairPlan = TaskHierarchyRepairPlan(canonicalTasks: canonicalTasks)
        let effectiveParentIDByTaskID = canonicalTasks.reduce(
            into: [UUID: UUID?]()
        ) { result, task in
            result[task.id] = repairPlan.taskIDsToDisplayAsRoots.contains(task.id)
                ? nil
                : task.parentID
        }

        let assignmentWinners = taskCategoryAssignments
            .deduplicatedByID()
            .logicalWinnersByTaskID()
        let activeAssignmentByTaskID = assignmentWinners.reduce(
            into: [UUID: TaskCategoryAssignment]()
        ) { result, pair in
            let assignment = pair.value
            guard assignment.deletedAt == nil,
                  taskIDs.contains(pair.key),
                  categoryIDs.contains(assignment.categoryID)
            else {
                return
            }
            result[pair.key] = assignment
        }

        let visualWinners = checklistVisuals
            .deduplicatedByID()
            .logicalWinnersByChecklistItemID()
        let canonicalChecklistItems = checklistItems
            .visibleDeduplicatedByID()
            .filter { taskIDs.contains($0.taskID) }
        let checklistItemIDs = Set(canonicalChecklistItems.map(\.id))
        let activeVisualByItemID = visualWinners.reduce(
            into: [UUID: ChecklistItemVisual]()
        ) { result, pair in
            guard pair.value.deletedAt == nil,
                  checklistItemIDs.contains(pair.key)
            else {
                return
            }
            result[pair.key] = pair.value
        }
        let quantityGoalByTaskID = quantityGoals
            .visibleDeduplicatedByID()
            .reduce(into: [UUID: TaskQuantityGoal]()) { result, goal in
                guard taskIDs.contains(goal.taskID),
                      goal.id == TaskProgressIdentity.quantityGoalID(
                          taskID: goal.taskID
                      )
                else {
                    return
                }
                result[goal.taskID] = goal
            }
        let recurrenceRuleByTaskID = recurrenceRules
            .visibleDeduplicatedByID()
            .reduce(into: [UUID: TaskRecurrenceRule]()) { result, rule in
                guard taskIDs.contains(rule.templateTaskID),
                      rule.id == TaskProgressIdentity.recurrenceRuleID(
                          templateTaskID: rule.templateTaskID
                      ),
                      rule.cadenceRaw == TaskRecurrenceCadence.daily.rawValue
                else {
                    return
                }
                result[rule.templateTaskID] = rule
            }

        snapshot = AITaskWorkspaceSnapshot(
            categories: canonicalCategories.map { category in
                AITaskWorkspaceCategory(
                    id: category.id,
                    title: category.title,
                    iconName: ChecklistVisualSanitizer.sanitizedIcon(
                        category.iconName
                    ),
                    colorHex: ChecklistVisualSanitizer.sanitizedColor(
                        category.colorHex
                    ),
                    includesInForecast: category.includesInForecast,
                    sortOrder: category.sortOrder
                )
            },
            tasks: canonicalTasks.map { task in
                let effectiveParentID = effectiveParentIDByTaskID[task.id] ?? nil
                return AITaskWorkspaceTask(
                    id: task.id,
                    title: task.title,
                    parentID: effectiveParentID,
                    categoryID: effectiveParentID == nil
                        ? activeAssignmentByTaskID[task.id]?.categoryID
                        : nil,
                    path: task.title,
                    notes: task.notes ?? "",
                    estimatedMinutes: TaskEstimatePolicy
                        .normalized(seconds: task.estimatedSeconds)
                        .map { $0 / 60 },
                    dueAt: task.dueAt,
                    iconName: ChecklistVisualSanitizer.sanitizedIcon(
                        task.iconName
                    ),
                    colorHex: ChecklistVisualSanitizer.sanitizedColor(
                        task.colorHex
                    ),
                    sortOrder: task.sortOrder,
                    isArchived: task.isArchivedForLifecycle,
                    quantityGoal: quantityGoalByTaskID[task.id].map(
                        TaskQuantityGoalDraft.init
                    ),
                    dailyRecurrence: recurrenceRuleByTaskID[task.id].map(
                        TaskDailyRecurrenceDraft.init
                    )
                )
            },
            checklistItems: canonicalChecklistItems.map { item in
                let visual = activeVisualByItemID[item.id]
                return AITaskWorkspaceChecklistItem(
                    id: item.id,
                    taskID: item.taskID,
                    title: item.title,
                    isCompleted: item.isCompleted,
                    iconName: ChecklistVisualSanitizer.sanitizedIcon(
                        visual?.iconName
                    ),
                    colorHex: ChecklistVisualSanitizer.sanitizedColor(
                        visual?.colorHex
                    ),
                    sortOrder: item.sortOrder
                )
            }
        )

        baselines = AITaskWorkspaceMutationBaselines(
            categoryMutationIDs: canonicalCategories.reduce(into: [:]) {
                $0[$1.id] = $1.clientMutationID
            },
            taskMutationIDs: canonicalTasks.reduce(into: [:]) {
                $0[$1.id] = $1.clientMutationID
            },
            categoryAssignmentMutationIDsByTaskID:
            activeAssignmentByTaskID.reduce(into: [:]) {
                $0[$1.key] = $1.value.clientMutationID
            },
            checklistItemMutationIDs: canonicalChecklistItems.reduce(into: [:]) {
                $0[$1.id] = $1.clientMutationID
            },
            checklistVisualMutationIDsByItemID:
            activeVisualByItemID.reduce(into: [:]) {
                $0[$1.key] = $1.value.clientMutationID
            }
        )
    }
}

private extension AITaskWorkspaceSnapshot {
    struct FingerprintFacts: Encodable {
        let schemaVersion: Int
        let categories: [AITaskWorkspaceCategory]
        let tasks: [AITaskWorkspaceTask]
        let checklistItems: [AITaskWorkspaceChecklistItem]
    }

    static let comparisonLocale = Locale(identifier: "en_US_POSIX")

    static func contextFingerprint(
        schemaVersion: Int,
        categories: [AITaskWorkspaceCategory],
        tasks: [AITaskWorkspaceTask],
        checklistItems: [AITaskWorkspaceChecklistItem]
    ) -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .iso8601
        // Every value in FingerprintFacts uses app-owned, nonthrowing Codable
        // synthesis. A failure here is an internal contract violation rather
        // than a provider or user-data recovery path.
        let data = try! encoder.encode(
            FingerprintFacts(
                schemaVersion: schemaVersion,
                categories: categories,
                tasks: tasks,
                checklistItems: checklistItems
            )
        )
        return SHA256.hash(data: data)
            .map { String(format: "%02x", $0) }
            .joined()
    }

    static func canonicalCategories(
        _ categories: [AITaskWorkspaceCategory]
    ) -> [AITaskWorkspaceCategory] {
        categories.sorted { lhs, rhs in
            if lhs.sortOrder != rhs.sortOrder {
                return lhs.sortOrder < rhs.sortOrder
            }
            return stableTextAndIDOrder(
                lhs: lhs.title,
                lhsID: lhs.id,
                rhs: rhs.title,
                rhsID: rhs.id
            )
        }
    }

    static func canonicalTasks(
        _ tasks: [AITaskWorkspaceTask]
    ) -> [AITaskWorkspaceTask] {
        let deterministicallySeeded = tasks.sorted { lhs, rhs in
            stableTextAndIDOrder(
                lhs: lhs.title,
                lhsID: lhs.id,
                rhs: rhs.title,
                rhsID: rhs.id
            )
        }
        let taskByID = deterministicallySeeded.reduce(
            into: [UUID: AITaskWorkspaceTask]()
        ) { result, task in
            if result[task.id] == nil {
                result[task.id] = task
            }
        }
        let withPaths = deterministicallySeeded.map { task -> AITaskWorkspaceTask in
            var updated = task
            updated.path = fullPath(for: task, taskByID: taskByID)
            return updated
        }
        return withPaths.sorted { lhs, rhs in
            let lhsKey = normalizedComparisonKey(lhs.path)
            let rhsKey = normalizedComparisonKey(rhs.path)
            if lhsKey != rhsKey {
                return lhsKey < rhsKey
            }
            if lhs.path != rhs.path {
                return lhs.path < rhs.path
            }
            if lhs.sortOrder != rhs.sortOrder {
                return lhs.sortOrder < rhs.sortOrder
            }
            return lhs.id.uuidString < rhs.id.uuidString
        }
    }

    static func canonicalChecklistItems(
        _ checklistItems: [AITaskWorkspaceChecklistItem],
        tasks: [AITaskWorkspaceTask]
    ) -> [AITaskWorkspaceChecklistItem] {
        let taskRank = tasks.enumerated().reduce(into: [UUID: Int]()) {
            if $0[$1.element.id] == nil {
                $0[$1.element.id] = $1.offset
            }
        }
        return checklistItems.sorted { lhs, rhs in
            let lhsRank = taskRank[lhs.taskID] ?? .max
            let rhsRank = taskRank[rhs.taskID] ?? .max
            if lhsRank != rhsRank {
                return lhsRank < rhsRank
            }
            if lhs.sortOrder != rhs.sortOrder {
                return lhs.sortOrder < rhs.sortOrder
            }
            return stableTextAndIDOrder(
                lhs: lhs.title,
                lhsID: lhs.id,
                rhs: rhs.title,
                rhsID: rhs.id
            )
        }
    }

    static func fullPath(
        for task: AITaskWorkspaceTask,
        taskByID: [UUID: AITaskWorkspaceTask]
    ) -> String {
        var components: [String] = []
        var visited = Set<UUID>()
        var cursor: AITaskWorkspaceTask? = task

        while let current = cursor, visited.insert(current.id).inserted {
            components.append(current.title)
            cursor = current.parentID.flatMap { taskByID[$0] }
        }
        return components.reversed().joined(separator: " / ")
    }

    static func stableTextAndIDOrder(
        lhs: String,
        lhsID: UUID,
        rhs: String,
        rhsID: UUID
    ) -> Bool {
        let lhsKey = normalizedComparisonKey(lhs)
        let rhsKey = normalizedComparisonKey(rhs)
        if lhsKey != rhsKey {
            return lhsKey < rhsKey
        }
        if lhs != rhs {
            return lhs < rhs
        }
        return lhsID.uuidString < rhsID.uuidString
    }

    static func normalizedComparisonKey(_ value: String) -> String {
        value.folding(
            options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive],
            locale: comparisonLocale
        )
    }
}
