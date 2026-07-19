import Foundation

struct TaskHierarchyProjection: Equatable {
    struct Section: Identifiable, Equatable {
        enum Kind: Equatable {
            case hierarchy
            case searchResults
        }

        let id: String
        let categoryID: UUID?
        let title: String
        let iconName: String
        let colorHex: String?
        let includesInForecast: Bool
        let kind: Kind
        let items: [Item]

        var taskTreeSectionModel: TaskTreeVisibleSectionModel {
            TaskTreeVisibleSectionModel(
                id: id,
                categoryID: categoryID,
                title: title,
                iconName: iconName,
                colorHex: colorHex,
                includesInForecast: includesInForecast,
                rows: items.map {
                    TaskTreeRowModel(
                        taskID: $0.id,
                        depth: $0.depth,
                        childCount: $0.childCount,
                        isExpanded: $0.isExpanded
                    )
                }
            )
        }
    }

    struct Item: Identifiable, Equatable {
        let identity: TaskIdentityPresentation
        let depth: Int
        let childCount: Int
        let isExpanded: Bool
        let isAvailable: Bool
        let isRunning: Bool
        let checklistProgress: ChecklistProgress?
        let workedSeconds: Int
        let unavailableReason: String?
        let timerCommand: TimerPickerSelectionCommand

        var id: UUID { identity.id }
        var hasChildren: Bool { childCount > 0 }
    }

    let sections: [Section]
    let runningItems: [Item]
    let isSearching: Bool
    let hasVisibleTasks: Bool

    init(
        store: TimeTrackerStore,
        expandedTaskIDs: Set<UUID>,
        searchText: String
    ) {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        isSearching = query.isEmpty == false
        hasVisibleTasks = store.visibleTaskCount > 0
        runningItems = Self.runningItems(store: store, matching: query)

        if query.isEmpty {
            sections = store.taskTreeSections(expandedTaskIDs: expandedTaskIDs).compactMap { section in
                let items = section.rows.compactMap { row in
                    Self.item(
                        store: store,
                        taskID: row.taskID,
                        depth: row.depth,
                        childCount: row.childCount,
                        isExpanded: row.isExpanded
                    )
                }
                guard items.isEmpty == false else { return nil }
                return Section(
                    id: section.id,
                    categoryID: section.categoryID,
                    title: section.title,
                    iconName: section.iconName,
                    colorHex: section.colorHex,
                    includesInForecast: section.includesInForecast,
                    kind: .hierarchy,
                    items: items
                )
            }
        } else {
            let items = store.taskSearchResults(matching: query).compactMap { task in
                Self.item(
                    store: store,
                    taskID: task.id,
                    depth: 0,
                    childCount: store.visibleChildCount(for: task.id),
                    isExpanded: false
                )
            }
            sections = items.isEmpty
                ? []
                : [
                    Section(
                        id: "task-hierarchy-search-results",
                        categoryID: nil,
                        title: AppStrings.localized("tasks.searchResults"),
                        iconName: "magnifyingglass",
                        colorHex: nil,
                        includesInForecast: true,
                        kind: .searchResults,
                        items: items
                    )
                ]
        }
    }

    private static func runningItems(
        store: TimeTrackerStore,
        matching query: String
    ) -> [Item] {
        var seenTaskIDs = Set<UUID>()
        return store.activeSegments.compactMap { segment in
            guard seenTaskIDs.insert(segment.taskID).inserted,
                  let task = store.task(for: segment.taskID) else {
                return nil
            }
            let identity = store.taskIdentityPresentation(for: task)
            guard query.isEmpty ||
                    task.title.localizedCaseInsensitiveContains(query) ||
                    identity.fullPath.localizedCaseInsensitiveContains(query) ||
                    (task.notes?.localizedCaseInsensitiveContains(query) ?? false) else {
                return nil
            }
            return item(
                store: store,
                taskID: task.id,
                depth: 0,
                childCount: store.visibleChildCount(for: task.id),
                isExpanded: false
            )
        }
    }

    private static func item(
        store: TimeTrackerStore,
        taskID: UUID,
        depth: Int,
        childCount: Int,
        isExpanded: Bool
    ) -> Item? {
        guard let task = store.task(for: taskID) else { return nil }
        let isAvailable = store.isTaskAvailableForTracking(task)
        let checklistProgress = store.checklistProgress(for: task.id)
        let rollup = store.rollup(for: task.id)
        return Item(
            identity: store.taskIdentityPresentation(for: task),
            depth: depth,
            childCount: childCount,
            isExpanded: isExpanded,
            isAvailable: isAvailable,
            isRunning: store.activeSegment(for: task.id) != nil,
            checklistProgress: checklistProgress.totalCount > 0
                ? checklistProgress
                : nil,
            workedSeconds: rollup?.workedSeconds
                ?? store.secondsForTaskTotalRollup(task),
            unavailableReason: isAvailable
                ? nil
                : AppStrings.localized("task.parentUnavailable"),
            timerCommand: store.timerPickerSelectionCommand(for: task)
        )
    }
}
