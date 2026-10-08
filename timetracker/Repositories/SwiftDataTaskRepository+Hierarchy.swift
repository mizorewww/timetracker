import Foundation

nonisolated extension SwiftDataTaskRepository {
    func canMove(nodeID: UUID, to newParentID: UUID?, nodes: [TaskNode]) -> Bool {
        guard let node = nodes.first(where: { $0.id == nodeID }) else { return false }
        let isChangingParent = node.parentID != newParentID
        guard isChangingParent else { return true }
        let availabilityService = TaskTrackingAvailabilityService()
        if availabilityService.parentChangeBlocker(for: node) != nil {
            return false
        }
        guard let newParentID else { return true }
        guard nodeID != newParentID else { return false }
        guard nodes.contains(where: { $0.id == newParentID }) else { return false }
        if availabilityService.trackableTaskIDs(tasks: nodes).contains(newParentID) == false {
            return false
        }
        return !descendantIDs(of: nodeID, nodes: nodes).contains(newParentID)
    }

    func descendantIDs(of nodeID: UUID, nodes: [TaskNode]) -> Set<UUID> {
        let childrenByParentID = Dictionary(grouping: nodes) { $0.parentID }
        var pending = childrenByParentID[nodeID] ?? []
        var visited: Set<UUID> = [nodeID]
        var result = Set<UUID>()

        while let child = pending.popLast() {
            guard visited.insert(child.id).inserted else { continue }
            result.insert(child.id)
            pending.append(contentsOf: childrenByParentID[child.id] ?? [])
        }
        return result
    }

    func applyHierarchy(
        to node: TaskNode,
        parentID: UUID?
    ) throws {
        if let parentID {
            guard let parent = try task(id: parentID) else {
                throw TaskRepositoryError.invalidMove
            }
            guard try TaskTrackingAvailabilityService()
                .trackableTaskIDs(tasks: allNodes())
                .contains(parentID)
            else {
                throw TaskRepositoryError.invalidMove
            }
            node.depth = parent.depth + 1
            node.path = TaskHierarchyMetadata.canonicalPath(for: node.id)
        } else {
            node.depth = 0
            node.path = TaskHierarchyMetadata.canonicalPath(for: node.id)
        }
    }

    func updateDescendantHierarchy(of node: TaskNode, nodes: [TaskNode], now: Date) {
        let childrenByParentID = Dictionary(grouping: nodes) { $0.parentID }
        var pending = (childrenByParentID[node.id] ?? []).map { child in
            (node: child, depth: node.depth + 1)
        }
        var visited: Set<UUID> = [node.id]

        while let next = pending.popLast() {
            guard visited.insert(next.node.id).inserted else { continue }
            let expectedPath = TaskHierarchyMetadata.canonicalPath(for: next.node.id)
            if next.node.depth != next.depth || next.node.path != expectedPath {
                next.node.depth = next.depth
                next.node.path = expectedPath
                next.node.updatedAt = now
                next.node.deviceID = deviceID
                next.node.clientMutationID = UUID()
            }

            pending.append(contentsOf: (childrenByParentID[next.node.id] ?? []).map { child in
                (node: child, depth: next.depth + 1)
            })
        }
    }
}
