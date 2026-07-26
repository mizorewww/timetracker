import Foundation

extension TimeTrackerStore {
    func llmTaskCandidates() -> [LLMTaskCandidate] {
        let availableTasks = tasks.filter(isTaskEligibleAsParent)
        var pinnedIDs = Set<UUID>()
        let pinnedTasks: [TaskNode] = preferences.quickStartTaskIDs.compactMap {
            taskID -> TaskNode? in
            guard pinnedIDs.insert(taskID).inserted,
                  let task = taskByID[taskID],
                  isTaskEligibleAsParent(task)
            else {
                return nil
            }
            return task
        }
        let frequentTasks = frequentRecentTasks(
            excluding: pinnedIDs,
            limit: availableTasks.count
        )
        let priorityIDs = Set((pinnedTasks + frequentTasks).map(\.id))
        let remainingTasks = availableTasks
            .filter { !priorityIDs.contains($0.id) }
            .sorted { lhs, rhs in
                let lhsPath = taskPath(for: lhs)
                let rhsPath = taskPath(for: rhs)
                let lhsKey = lhsPath.lowercased()
                let rhsKey = rhsPath.lowercased()
                if lhsKey != rhsKey {
                    return lhsKey < rhsKey
                }
                if lhsPath != rhsPath {
                    return lhsPath < rhsPath
                }
                return lhs.id.uuidString < rhs.id.uuidString
            }

        return LLMSuggestionInputPolicy.completeCandidates(
            (pinnedTasks + frequentTasks + remainingTasks).map { task in
                LLMTaskCandidate(
                    id: task.id,
                    title: task.title,
                    path: taskPath(for: task),
                    iconName: ChecklistVisualSanitizer.sanitizedIcon(
                        task.iconName
                    ),
                    colorHex: ChecklistVisualSanitizer.sanitizedColor(
                        task.colorHex
                    )
                )
            }
        )
    }

    func llmCategoryCandidates() -> [LLMCategoryCandidate] {
        let availableCategories = taskCategories
            .visibleDeduplicatedByID()
            .sorted { lhs, rhs in
                if lhs.sortOrder != rhs.sortOrder {
                    return lhs.sortOrder < rhs.sortOrder
                }
                let lhsKey = lhs.title.lowercased()
                let rhsKey = rhs.title.lowercased()
                if lhsKey != rhsKey {
                    return lhsKey < rhsKey
                }
                if lhs.title != rhs.title {
                    return lhs.title < rhs.title
                }
                return lhs.id.uuidString < rhs.id.uuidString
            }
            .map { category in
                LLMCategoryCandidate(
                    id: category.id,
                    title: category.title,
                    iconName: ChecklistVisualSanitizer.sanitizedIcon(
                        category.iconName ??
                            ChecklistVisualSanitizer.defaultIcon
                    ),
                    colorHex: ChecklistVisualSanitizer.sanitizedColor(
                        category.colorHex ??
                            ChecklistVisualSanitizer.defaultColor
                    )
                )
            }
        return LLMSuggestionInputPolicy.completeCategoryCandidates(
            availableCategories
        )
    }

    func llmInboxSuggestionCandidates() -> LLMInboxSuggestionCandidates {
        LLMSuggestionInputPolicy.completeDestinationCandidates(
            tasks: llmTaskCandidates(),
            categories: llmCategoryCandidates()
        )
    }
}
