import Foundation

struct TaskInitialExpansionPolicy {
    var fullExpansionLimit = 750
    var shallowExpansionLimit = 3_000

    func expandedTaskIDs(for tasks: [TaskNode]) -> Set<UUID> {
        if tasks.count <= fullExpansionLimit {
            return Set(tasks.map(\.id))
        }

        let maxExpandedDepth = tasks.count <= shallowExpansionLimit ? 1 : 0
        return Set(tasks.filter { $0.depth <= maxExpandedDepth }.map(\.id))
    }
}
