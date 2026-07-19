import Foundation

struct TaskTreeIndexes {
    static let empty = TaskTreeIndexes(
        orderedTaskIDs: [],
        taskByID: [:],
        childrenByParentID: [:],
        taskIDsToDisplayAsRoots: [],
        taskPathByID: [:],
        taskParentPathByID: [:],
        taskBreadcrumbByID: [:]
    )

    let orderedTaskIDs: [UUID]
    let taskByID: [UUID: TaskNode]
    let childrenByParentID: [UUID?: [TaskNode]]
    let taskIDsToDisplayAsRoots: Set<UUID>
    let taskPathByID: [UUID: String]
    let taskParentPathByID: [UUID: String]
    let taskBreadcrumbByID: [UUID: TaskBreadcrumbPresentation]
}

struct TaskTreeProjectionOperationCounts: Equatable {
    let visitedTaskCount: Int
    let childBucketLookupCount: Int
}

struct TaskTreeRowProjection: Equatable {
    let rows: [TaskTreeRowModel]
    let operationCounts: TaskTreeProjectionOperationCounts
}

struct TaskTreeProjection: Equatable {
    let sections: [TaskTreeVisibleSectionModel]
    let operationCounts: TaskTreeProjectionOperationCounts
}

struct TaskTreeSearchProjection: Equatable {
    let taskIDs: [UUID]
    let inspectedTaskCount: Int
}

struct TaskTreeRowModel: Identifiable, Equatable {
    let taskID: UUID
    let depth: Int
    let childCount: Int
    let isExpanded: Bool

    var id: UUID { taskID }
    var hasChildren: Bool { childCount > 0 }
}

struct TaskTreeCategorySectionModel: Identifiable {
    let id: String
    let categoryID: UUID?
    let title: String
    let iconName: String
    let colorHex: String?
    let includesInForecast: Bool
    let rootTasks: [TaskNode]
}

struct TaskTreeVisibleSectionModel: Identifiable, Equatable {
    let id: String
    let categoryID: UUID?
    let title: String
    let iconName: String
    let colorHex: String?
    let includesInForecast: Bool
    let rows: [TaskTreeRowModel]
}

struct TaskExpansionState: Equatable {
    private(set) var expandedTaskIDs: Set<UUID> = []

    func contains(_ taskID: UUID) -> Bool {
        expandedTaskIDs.contains(taskID)
    }

    mutating func toggle(_ taskID: UUID) {
        if expandedTaskIDs.contains(taskID) {
            expandedTaskIDs.remove(taskID)
        } else {
            expandedTaskIDs.insert(taskID)
        }
    }

    mutating func expand(_ taskID: UUID) {
        expandedTaskIDs.insert(taskID)
    }

    mutating func collapse(_ taskID: UUID) {
        expandedTaskIDs.remove(taskID)
    }
}
