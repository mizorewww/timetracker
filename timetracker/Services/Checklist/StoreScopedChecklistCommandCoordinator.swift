import Foundation
import SwiftData

struct ChecklistMutationBaseline: Equatable, Sendable {
    let itemID: UUID
    let taskID: UUID
    let clientMutationID: UUID

    init(item: ChecklistItem) {
        itemID = item.id
        taskID = item.taskID
        clientMutationID = item.clientMutationID
    }
}

struct ChecklistOrderMutationBaseline: Equatable, Sendable {
    let taskID: UUID
    let itemMutationIDs: [UUID: UUID]

    init(taskID: UUID, items: [ChecklistItem]) {
        self.taskID = taskID
        itemMutationIDs = items.reduce(into: [:]) { result, item in
            result[item.id] = item.clientMutationID
        }
    }
}

enum StoreScopedChecklistMutationError: LocalizedError, Equatable {
    case taskUnavailable
    case itemUnavailable
    case checklistChanged

    var errorDescription: String? {
        switch self {
        case .taskUnavailable:
            AppStrings.localized("systemAction.error.taskNotFound")
        case .itemUnavailable:
            AppStrings.localized("checklist.error.unavailable")
        case .checklistChanged:
            AppStrings.localized("checklist.error.changed")
        }
    }
}

struct ChecklistMutationOutcome: Equatable {
    let taskID: UUID
    let itemID: UUID?
    let didMutate: Bool
    let affectedAncestorIDs: Set<UUID>

    var events: Set<StoreDomainEvent> {
        guard didMutate else { return [] }
        return [
            .checklistChanged(
                taskID: taskID,
                affectedAncestorIDs: affectedAncestorIDs
            ),
        ]
    }
}

/// Serializes quick checklist commands with task-editor replacement and task
/// lifecycle writes. Every command resolves its task, item, ordering, and
/// hierarchy only after the shared store lock is held.
@MainActor
struct StoreScopedChecklistCommandCoordinator {
    let container: ModelContainer
    let writeAuthorization: StoreWriteAuthorization
    let deviceID: String
    let nowProvider: () -> Date

    init(
        container: ModelContainer,
        writeAuthorization: StoreWriteAuthorization = .applicationState,
        deviceID: String = DeviceIdentity.current,
        nowProvider: @escaping () -> Date = Date.init
    ) {
        self.container = container
        self.writeAuthorization = writeAuthorization
        self.deviceID = deviceID
        self.nowProvider = nowProvider
    }

    func add(taskID: UUID, title: String) throws -> ChecklistMutationOutcome {
        let preparedTitle = try ChecklistDraftPersistencePolicy.prepare([
            ChecklistEditorDraft(title: title),
        ])[0].title
        return try withCanonicalTask(taskID: taskID) { context, _ in
            let existingItems = try visibleItems(taskID: taskID, context: context)
            guard let item = try ChecklistCommandHandler().add(
                taskID: taskID,
                title: preparedTitle,
                existingItems: existingItems,
                context: context,
                deviceID: deviceID
            ) else {
                throw ChecklistDraftValidationError.emptyTitle(index: 0)
            }
            return (item.id, true)
        }
    }

    func setCompletion(
        baseline: ChecklistMutationBaseline,
        isCompleted: Bool
    ) throws -> ChecklistMutationOutcome {
        try withCanonicalTask(taskID: baseline.taskID) { context, _ in
            let items = try visibleItems(taskID: baseline.taskID, context: context)
            guard let item = items.first(where: { $0.id == baseline.itemID }) else {
                throw StoreScopedChecklistMutationError.itemUnavailable
            }
            guard item.clientMutationID == baseline.clientMutationID else {
                throw StoreScopedChecklistMutationError.checklistChanged
            }
            guard item.isCompleted != isCompleted else {
                return (item.id, false)
            }
            try ChecklistCommandHandler().setCompletion(
                item,
                isCompleted: isCompleted,
                existingItems: items,
                context: context,
                now: nowProvider(),
                deviceID: deviceID
            )
            return (item.id, true)
        }
    }

    func reorder(
        baseline: ChecklistOrderMutationBaseline,
        orderedItemIDs: [UUID]
    ) throws -> ChecklistMutationOutcome {
        try withCanonicalTask(taskID: baseline.taskID) { context, _ in
            let items = try visibleItems(taskID: baseline.taskID, context: context)
            let currentMutationIDs = items.reduce(into: [UUID: UUID]()) {
                $0[$1.id] = $1.clientMutationID
            }
            guard currentMutationIDs == baseline.itemMutationIDs,
                  orderedItemIDs.count == items.count,
                  Set(orderedItemIDs) == Set(items.map(\.id))
            else {
                throw StoreScopedChecklistMutationError.checklistChanged
            }
            let currentOrder = Self.ordered(items).map(\.id)
            guard currentOrder != orderedItemIDs else {
                return (nil, false)
            }
            try ChecklistCommandHandler().reorder(
                taskID: baseline.taskID,
                orderedItemIDs: orderedItemIDs,
                context: context,
                now: nowProvider(),
                deviceID: deviceID
            )
            return (nil, true)
        }
    }

    func withCanonicalTask(
        taskID: UUID,
        operation: (ModelContext, [TaskNode]) throws -> (itemID: UUID?, didMutate: Bool)
    ) throws -> ChecklistMutationOutcome {
        try writeAuthorization.requireUserWritesAllowed()
        let scope = try TimerStoreScope(container: container)
        let transaction = StoreScopedTimerMutationTransaction(
            scope: scope,
            container: container
        )
        return try transaction.withFreshContext(author: .localMutation) { context in
            let tasks = try SwiftDataTaskRepository(
                context: context,
                deviceID: deviceID
            ).allNodes()
            guard tasks.contains(where: { $0.id == taskID }) else {
                throw StoreScopedChecklistMutationError.taskUnavailable
            }
            let result = try operation(context, tasks)
            let taskByID = Dictionary(uniqueKeysWithValues: tasks.map { ($0.id, $0) })
            let ancestorIDs = Set(
                StoreSelectionCoordinator().ancestorTaskIDs(
                    for: taskID,
                    taskByID: taskByID
                )
            )
            return ChecklistMutationOutcome(
                taskID: taskID,
                itemID: result.itemID,
                didMutate: result.didMutate,
                affectedAncestorIDs: ancestorIDs
            )
        }
    }

    func visibleItems(taskID: UUID, context: ModelContext) throws -> [ChecklistItem] {
        let requestedTaskID = taskID
        return try context.fetch(
            FetchDescriptor<ChecklistItem>(
                predicate: #Predicate { $0.taskID == requestedTaskID }
            )
        ).visibleDeduplicatedByID()
    }

    private static func ordered(_ items: [ChecklistItem]) -> [ChecklistItem] {
        items.sorted { lhs, rhs in
            if lhs.isCompleted != rhs.isCompleted {
                return !lhs.isCompleted
            }
            if lhs.sortOrder != rhs.sortOrder {
                return lhs.sortOrder < rhs.sortOrder
            }
            if lhs.createdAt != rhs.createdAt {
                return lhs.createdAt < rhs.createdAt
            }
            return lhs.id.uuidString < rhs.id.uuidString
        }
    }
}
