import Foundation

extension SwiftDataTaskRepository {
    func canMove(nodeID: UUID, to newParentID: UUID?, nodes: [TaskNode]) -> Bool {
        guard let newParentID else { return true }
        guard nodeID != newParentID else { return false }
        return !descendantIDs(of: nodeID, nodes: nodes).contains(newParentID)
    }

    func descendantIDs(of nodeID: UUID, nodes: [TaskNode], visited: Set<UUID> = []) -> Set<UUID> {
        guard !visited.contains(nodeID) else { return [] }
        let nextVisited = visited.union([nodeID])
        let directChildren = nodes.filter { $0.parentID == nodeID }
        return directChildren.reduce(into: Set<UUID>()) { result, child in
            result.insert(child.id)
            result.formUnion(descendantIDs(of: child.id, nodes: nodes, visited: nextVisited))
        }
    }

    func applyHierarchy(to node: TaskNode, parentID: UUID?) throws {
        if let parentID, let parent = try task(id: parentID) {
            node.depth = parent.depth + 1
            node.path = parent.path + "/" + node.id.uuidString
        } else {
            node.depth = 0
            node.path = "/" + node.id.uuidString
        }
    }

    func updateDescendantHierarchy(of node: TaskNode) throws {
        let children = try children(of: node.id)
        for child in children {
            child.depth = node.depth + 1
            child.path = node.path + "/" + child.id.uuidString
            child.updatedAt = Date()
            try updateDescendantHierarchy(of: child)
        }
    }
}
