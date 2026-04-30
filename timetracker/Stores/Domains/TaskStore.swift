import Foundation

struct TaskStore {
    private(set) var tasks: [TaskNode] = []
    private(set) var categories: [TaskCategory] = []

    mutating func refresh(repository: TaskRepository) throws {
        tasks = try repository.allNodes()
        categories = try repository.categories()
    }
}
