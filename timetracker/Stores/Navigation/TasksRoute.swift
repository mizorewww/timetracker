import Foundation

enum TasksRoute: Hashable, Sendable {
    case detail(taskID: UUID)

    var taskID: UUID {
        switch self {
        case let .detail(taskID):
            taskID
        }
    }
}
