import Foundation

struct TaskCategoryOrderMutationBaseline: Equatable, Sendable {
    let categoryMutationIDs: [UUID: UUID]
    let orderedCategoryIDs: [UUID]

    init(categories: [TaskCategory]) {
        categoryMutationIDs = categories.reduce(into: [:]) { result, category in
            result[category.id] = category.clientMutationID
        }
        orderedCategoryIDs = Self.ordered(categories).map(\.id)
    }

    private static func ordered(_ categories: [TaskCategory]) -> [TaskCategory] {
        categories.sorted { lhs, rhs in
            if lhs.sortOrder != rhs.sortOrder { return lhs.sortOrder < rhs.sortOrder }
            if lhs.createdAt != rhs.createdAt { return lhs.createdAt < rhs.createdAt }
            return lhs.id.uuidString < rhs.id.uuidString
        }
    }
}

struct TaskCategoryOrderMutationOutcome: Equatable {
    let affectedCategoryIDs: Set<UUID>
    let didMutate: Bool

    var events: Set<StoreDomainEvent> {
        guard didMutate else { return [] }
        return [.taskChanged(taskID: nil, affectedAncestorIDs: [])]
    }
}
