import Foundation

struct TaskStore {
    private(set) var tasks: [TaskNode] = []

    mutating func refresh(repository: TaskRepository) throws {
        tasks = try repository.allNodes()
    }
}
