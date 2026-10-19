import Foundation

struct TaskCategoryOrderMutationOutcome: Equatable {
    let affectedCategoryIDs: Set<UUID>
    let didMutate: Bool

    var events: Set<StoreDomainEvent> {
        guard didMutate else { return [] }
        return [.taskChanged(taskID: nil, affectedAncestorIDs: [])]
    }
}
