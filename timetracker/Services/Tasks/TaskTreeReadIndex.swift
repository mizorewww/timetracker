import Foundation

struct TaskTreeSectionIndex: Identifiable, Equatable {
    let id: String
    let categoryID: UUID?
    let title: String
    let iconName: String
    let colorHex: String?
    let includesInForecast: Bool
    let rootTaskIDs: [UUID]
}

struct TaskTreeSearchEntry: Equatable {
    let taskID: UUID
    let title: String
    let path: String
    let notes: String?

    func matches(_ query: String) -> Bool {
        title.localizedCaseInsensitiveContains(query) ||
            path.localizedCaseInsensitiveContains(query) ||
            (notes?.localizedCaseInsensitiveContains(query) ?? false)
    }
}

/// Immutable hierarchy facts rebuilt by `TimeTrackerStore` only when task or
/// category mutations change their semantic value. SwiftUI projections consume
/// IDs and value types from this index; they never sort, filter children, or
/// walk ancestor title paths in a row body.
struct TaskTreeReadIndex: Equatable {
    static let empty = TaskTreeReadIndex(
        visibleChildIDsByParentID: [:],
        sections: [],
        searchEntries: []
    )

    let visibleChildIDsByParentID: [UUID?: [UUID]]
    let sections: [TaskTreeSectionIndex]
    let searchEntries: [TaskTreeSearchEntry]

    var rootTaskIDs: [UUID] {
        visibleChildIDsByParentID[nil] ?? []
    }

    var visibleTaskCount: Int {
        searchEntries.count
    }

    func visibleChildCount(for taskID: UUID) -> Int {
        visibleChildIDsByParentID[taskID]?.count ?? 0
    }

    func projection(expandedTaskIDs: Set<UUID>) -> TaskTreeProjection {
        var visibleSections: [TaskTreeVisibleSectionModel] = []
        visibleSections.reserveCapacity(sections.count)
        var visitedTaskCount = 0
        var childBucketLookupCount = 0

        for section in sections {
            let rowProjection = TaskTreeFlattener.rowProjection(
                rootTaskIDs: section.rootTaskIDs,
                childTaskIDsByParentID: visibleChildIDsByParentID,
                expandedTaskIDs: expandedTaskIDs
            )
            visitedTaskCount += rowProjection.operationCounts.visitedTaskCount
            childBucketLookupCount += rowProjection.operationCounts.childBucketLookupCount
            visibleSections.append(
                TaskTreeVisibleSectionModel(
                    id: section.id,
                    categoryID: section.categoryID,
                    title: section.title,
                    iconName: section.iconName,
                    colorHex: section.colorHex,
                    includesInForecast: section.includesInForecast,
                    rows: rowProjection.rows
                )
            )
        }

        return TaskTreeProjection(
            sections: visibleSections,
            operationCounts: TaskTreeProjectionOperationCounts(
                visitedTaskCount: visitedTaskCount,
                childBucketLookupCount: childBucketLookupCount
            )
        )
    }

    func searchProjection(matching query: String) -> TaskTreeSearchProjection {
        var matchingTaskIDs: [UUID] = []
        matchingTaskIDs.reserveCapacity(Swift.min(searchEntries.count, 16))
        for entry in searchEntries where entry.matches(query) {
            matchingTaskIDs.append(entry.taskID)
        }
        return TaskTreeSearchProjection(
            taskIDs: matchingTaskIDs,
            inspectedTaskCount: searchEntries.count
        )
    }
}
