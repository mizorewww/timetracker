import Foundation
import SwiftData

enum StoreScopedChecklistMutationError: LocalizedError, Equatable {
    case taskUnavailable
    case itemUnavailable

    var errorDescription: String? {
        switch self {
        case .taskUnavailable:
            AppStrings.localized("systemAction.error.taskNotFound")
        case .itemUnavailable:
            AppStrings.localized("checklist.error.unavailable")
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
        taskID: UUID,
        itemID: UUID,
        isCompleted: Bool
    ) throws -> ChecklistMutationOutcome {
        try withCanonicalTask(taskID: taskID) { context, _ in
            let items = try visibleItems(taskID: taskID, context: context)
            guard let item = items.first(where: { $0.id == itemID }) else {
                throw StoreScopedChecklistMutationError.itemUnavailable
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

    /// Resolves the task and its parent chain by ID after the lock is held.
    /// The operation learns whether the branch can still receive work (no
    /// archived task on the chain); the outcome carries the ancestors whose
    /// rollups the checklist change affects.
    func withCanonicalTask(
        taskID: UUID,
        operation: (ModelContext, _ isTrackable: Bool) throws -> (itemID: UUID?, didMutate: Bool)
    ) throws -> ChecklistMutationOutcome {
        try session.withFreshMutationContext { context in
            let repository = SwiftDataTaskRepository(context: context, deviceID: deviceID)
            guard let task = try repository.task(id: taskID) else {
                throw StoreScopedChecklistMutationError.taskUnavailable
            }
            var ancestorIDs: Set<UUID> = []
            var isTrackable = task.isArchivedForLifecycle == false
            var cursor = task
            while let parentID = cursor.parentID, ancestorIDs.insert(parentID).inserted {
                guard let parent = try repository.task(id: parentID) else { break }
                isTrackable = isTrackable && parent.isArchivedForLifecycle == false
                cursor = parent
            }
            let result = try operation(context, isTrackable)
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
