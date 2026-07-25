import Foundation
import SwiftData

enum StoreScopedTaskCategoryMutationError: LocalizedError, Equatable {
    case categoryUnavailable
    case categoryChanged

    var errorDescription: String? {
        switch self {
        case .categoryUnavailable:
            AppStrings.localized("taskCategory.error.unavailable")
        case .categoryChanged:
            AppStrings.localized("taskCategory.error.changed")
        }
    }
}

struct TaskCategoryMutationOutcome: Equatable {
    let categoryID: UUID
    let didMutate: Bool

    var events: Set<StoreDomainEvent> {
        guard didMutate else { return [] }
        return [.taskChanged(taskID: nil, affectedAncestorIDs: [])]
    }
}

/// Coordinates category metadata and assignment deletion with task drafts in
/// the shared store mutation domain. Category identity is resolved only after
/// the lock is held; scene-owned SwiftData objects never cross this boundary.
@MainActor
struct StoreScopedTaskCategoryCommandCoordinator {
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

    func reorder(
        orderedCategoryIDs: [UUID],
        baseline: TaskCategoryOrderMutationBaseline
    ) throws -> TaskCategoryOrderMutationOutcome {
        try withFreshRepository { repository in
            let categories = try repository.categories()
            let currentBaseline = TaskCategoryOrderMutationBaseline(
                categories: categories
            )
            guard currentBaseline == baseline,
                  orderedCategoryIDs.count == categories.count,
                  Set(orderedCategoryIDs) == Set(categories.map(\.id))
            else {
                throw StoreScopedTaskCategoryMutationError.categoryChanged
            }
            guard currentBaseline.orderedCategoryIDs != orderedCategoryIDs else {
                return TaskCategoryOrderMutationOutcome(
                    affectedCategoryIDs: Set(orderedCategoryIDs),
                    didMutate: false
                )
            }

            let didMutate = try repository.reorderCategories(
                orderedCategoryIDs: orderedCategoryIDs,
                now: nowProvider()
            )
            return TaskCategoryOrderMutationOutcome(
                affectedCategoryIDs: Set(orderedCategoryIDs),
                didMutate: didMutate
            )
        }
    }

    func save(draft: TaskCategoryEditorDraft) throws -> TaskCategoryMutationOutcome {
        try withFreshRepository { repository in
            if let categoryID = draft.categoryID {
                guard let baseline = draft.baseline,
                      baseline.categoryID == categoryID
                else {
                    throw StoreScopedTaskCategoryMutationError.categoryChanged
                }
                let category = try requireCategory(
                    baseline: baseline,
                    repository: repository
                )
                let prepared = try TaskPersistencePolicy.prepareCategory(
                    title: draft.title,
                    colorHex: draft.colorHex,
                    iconName: draft.iconName
                )
                let didMutate = category.title != prepared.title ||
                    category.colorHex != prepared.colorHex ||
                    category.iconName != prepared.iconName ||
                    category.includesInForecast != draft.includesInForecast
                guard didMutate else {
                    return TaskCategoryMutationOutcome(
                        categoryID: categoryID,
                        didMutate: false
                    )
                }
                try repository.updateCategory(
                    categoryID: categoryID,
                    title: prepared.title,
                    colorHex: prepared.colorHex,
                    iconName: prepared.iconName,
                    includesInForecast: draft.includesInForecast
                )
                return TaskCategoryMutationOutcome(
                    categoryID: categoryID,
                    didMutate: true
                )
            }

            guard draft.baseline == nil else {
                throw StoreScopedTaskCategoryMutationError.categoryChanged
            }
            let category = try repository.createCategory(
                title: draft.title,
                colorHex: draft.colorHex,
                iconName: draft.iconName,
                includesInForecast: draft.includesInForecast
            )
            return TaskCategoryMutationOutcome(
                categoryID: category.id,
                didMutate: true
            )
        }
    }

    func delete(
        baseline: TaskCategoryMutationBaseline
    ) throws -> TaskCategoryMutationOutcome {
        try withFreshRepository { repository in
            _ = try requireCategory(baseline: baseline, repository: repository)
            try repository.softDeleteCategory(categoryID: baseline.categoryID)
            return TaskCategoryMutationOutcome(
                categoryID: baseline.categoryID,
                didMutate: true
            )
        }
    }

    private func withFreshRepository<Result>(
        _ operation: (SwiftDataTaskRepository) throws -> Result
    ) throws -> Result {
        try writeAuthorization.requireUserWritesAllowed()
        let scope = try TimerStoreScope(container: container)
        return try StoreScopedTimerMutationTransaction(
            scope: scope,
            container: container
        ).withFreshContext { context in
            try operation(
                SwiftDataTaskRepository(context: context, deviceID: deviceID)
            )
        }
    }

    private func requireCategory(
        baseline: TaskCategoryMutationBaseline,
        repository: SwiftDataTaskRepository
    ) throws -> TaskCategory {
        guard let category = try repository.category(id: baseline.categoryID) else {
            throw StoreScopedTaskCategoryMutationError.categoryUnavailable
        }
        guard category.clientMutationID == baseline.clientMutationID else {
            throw StoreScopedTaskCategoryMutationError.categoryChanged
        }
        return category
    }
}
