import Foundation

extension TaskTreeService {
    func readIndex(
        indexes: TaskTreeIndexes,
        visibleTaskIDs: Set<UUID>,
        categories: [TaskCategory],
        categoryIDByRootTaskID: [UUID: UUID]
    ) -> TaskTreeReadIndex {
        var visibleChildIDsByParentID: [UUID?: [UUID]] = [:]
        for (parentID, children) in indexes.childrenByParentID {
            let childIDs = children.compactMap { task in
                visibleTaskIDs.contains(task.id) ? task.id : nil
            }
            if parentID == nil || !childIDs.isEmpty {
                visibleChildIDsByParentID[parentID] = childIDs
            }
        }

        let rootTasks = (visibleChildIDsByParentID[nil] ?? []).compactMap { indexes.taskByID[$0] }
        let sectionIndexes = categorySections(
            rootTasks: rootTasks,
            categories: categories,
            categoryIDByRootTaskID: categoryIDByRootTaskID
        ).map { section in
            TaskTreeSectionIndex(
                id: section.id,
                categoryID: section.categoryID,
                title: section.title,
                iconName: section.iconName,
                colorHex: section.colorHex,
                includesInForecast: section.includesInForecast,
                rootTaskIDs: section.rootTasks.map(\.id)
            )
        }

        let searchEntries = indexes.orderedTaskIDs.compactMap { taskID -> TaskTreeSearchEntry? in
            guard visibleTaskIDs.contains(taskID),
                  let task = indexes.taskByID[taskID],
                  task.deletedAt == nil
            else {
                return nil
            }
            return TaskTreeSearchEntry(
                taskID: taskID,
                title: task.title,
                path: indexes.taskPathByID[taskID] ?? task.title,
                notes: task.notes
            )
        }

        return TaskTreeReadIndex(
            visibleChildIDsByParentID: visibleChildIDsByParentID,
            sections: sectionIndexes,
            searchEntries: searchEntries
        )
    }

    func categorySections(
        rootTasks: [TaskNode],
        categories: [TaskCategory],
        categoryIDByRootTaskID: [UUID: UUID]
    ) -> [TaskTreeCategorySectionModel] {
        let categories = categories.deduplicatedByID()
        let categoryByID = categories.reduce(into: [UUID: TaskCategory]()) { result, category in
            guard category.deletedAt == nil else { return }
            result[category.id] = category
        }
        let rootTasksByCategory = Dictionary(grouping: rootTasks) { task -> UUID? in
            guard let categoryID = categoryIDByRootTaskID[task.id], categoryByID[categoryID] != nil else { return nil }
            return categoryID
        }

        var sections: [TaskTreeCategorySectionModel] = []
        for category in categories where category.deletedAt == nil {
            sections.append(
                TaskTreeCategorySectionModel(
                    id: "category-\(category.id.uuidString)",
                    categoryID: category.id,
                    title: category.title,
                    iconName: category.iconName ?? "square.grid.2x2",
                    colorHex: category.colorHex,
                    includesInForecast: category.includesInForecast,
                    rootTasks: rootTasksByCategory[category.id] ?? []
                )
            )
        }

        if let uncategorized = rootTasksByCategory[nil], !uncategorized.isEmpty {
            sections.append(
                TaskTreeCategorySectionModel(
                    id: "uncategorized",
                    categoryID: nil,
                    title: AppStrings.localized("taskCategory.uncategorized"),
                    iconName: "tray",
                    colorHex: "8E8E93",
                    includesInForecast: true,
                    rootTasks: uncategorized
                )
            )
        }

        return sections
    }
}
