import Foundation

struct TaskStore {
    private(set) var tasks: [TaskNode] = []
    private(set) var categories: [TaskCategory] = []
    private(set) var categoryAssignments: [TaskCategoryAssignment] = []

    mutating func refresh(repository: TaskRepository) throws {
        tasks = try repository.allNodes()
        categories = try repository.categories()
        categoryAssignments = try repository.categoryAssignments()
    }
}
