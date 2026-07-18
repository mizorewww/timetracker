import Foundation

enum TasksRoute: Hashable, Sendable {
    case detail(taskID: UUID)
    case editor(taskID: UUID)

    var taskID: UUID {
        switch self {
        case .detail(let taskID), .editor(let taskID):
            taskID
        }
    }

    var startsEditing: Bool {
        switch self {
        case .detail:
            false
        case .editor:
            true
        }
    }
}
