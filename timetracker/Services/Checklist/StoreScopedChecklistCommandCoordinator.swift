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
    let session: StoreMutationSession
    let deviceID: String
    let nowProvider: () -> Date

    init(
        session: StoreMutationSession,
        deviceID: String = DeviceIdentity.current,
        nowProvider: @escaping () -> Date = Date.init
    ) {
        self.session = session
        self.deviceID = deviceID
        self.nowProvider = nowProvider
    }

    func add(taskID: UUID, title: String) throws -> ChecklistMutationOutcome {
        let preparedTitle = try ChecklistDraftPersistencePolicy.prepare([
            ChecklistEditorDraft(title: title),
        ])[0].title
        return try withCanonicalTask(taskID: taskID) { context, _ in
            let existingItems = try visibleItems(taskID: taskID, context: context)
            let item = ChecklistItem(
                taskID: taskID,
                title: preparedTitle,
                isCompleted: false,
                sortOrder: SortOrderPolicy.after(existingItems.map(\.sortOrder).max()),
                deviceID: deviceID
            )
            context.insert(item)
            context.insert(
                ChecklistItemVisual(
                    checklistItemID: item.id,
                    iconName: ChecklistVisualSanitizer.defaultIcon,
                    colorHex: ChecklistVisualSanitizer.defaultColor,
                    deviceID: deviceID
                )
            )
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
            let now = nowProvider()
            if isCompleted {
                item.sortOrderBeforeCompletion = item.sortOrder
            }
            if let restoredOrder = isCompleted ? nil : item.sortOrderBeforeCompletion {
                item.sortOrder = restoredOrder
                item.sortOrderBeforeCompletion = nil
            } else if let lastSiblingSortOrder = items.lazy
                .filter({ $0.id != item.id })
                .map(\.sortOrder)
                .max()
            {
                item.sortOrder = SortOrderPolicy.after(lastSiblingSortOrder)
            }
            item.isCompleted = isCompleted
            item.completedAt = isCompleted ? now : nil
            item.markMutated(at: now, deviceID: deviceID)
            return (item.id, true)
        }
    }

    func withCanonicalTask(
        taskID: UUID,
        operation: (ModelContext, [TaskNode]) throws -> (itemID: UUID?, didMutate: Bool)
    ) throws -> ChecklistMutationOutcome {
        try session.withFreshMutationContext { context in
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
}
