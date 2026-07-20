import Foundation

extension TimeTrackerStore {
    func llmTaskCandidates(
        maximumCount: Int = LLMSuggestionInputPolicy.maximumCandidateCount
    ) -> [LLMTaskCandidate] {
        let candidateLimit = min(
            max(0, maximumCount),
            LLMSuggestionInputPolicy.maximumCandidateCount
        )
        guard candidateLimit > 0 else { return [] }
        let availableTasks = tasks.filter(isTaskEligibleAsParent)
        var pinnedIDs = Set<UUID>()
        let pinnedTasks: [TaskNode] = preferences.quickStartTaskIDs.compactMap {
            taskID -> TaskNode? in
            guard pinnedIDs.insert(taskID).inserted,
                  let task = taskByID[taskID],
                  isTaskEligibleAsParent(task) else {
                return nil
            }
            return task
        }
        let frequentTasks = frequentRecentTasks(
            excluding: pinnedIDs,
            limit: candidateLimit
        )
        let priorityIDs = Set((pinnedTasks + frequentTasks).map(\.id))
        let remainingTasks = availableTasks
            .filter { !priorityIDs.contains($0.id) }
            .sorted { lhs, rhs in
                let lhsPath = taskPath(for: lhs)
                let rhsPath = taskPath(for: rhs)
                let lhsKey = lhsPath.lowercased()
                let rhsKey = rhsPath.lowercased()
                if lhsKey != rhsKey { return lhsKey < rhsKey }
                if lhsPath != rhsPath { return lhsPath < rhsPath }
                return lhs.id.uuidString < rhs.id.uuidString
            }
        let candidateWindow = (pinnedTasks + frequentTasks + remainingTasks)
            .prefix(candidateLimit)

        return LLMSuggestionInputPolicy.boundedCandidates(
            candidateWindow.map { task in
                LLMTaskCandidate(
                    id: task.id,
                    title: task.title,
                    path: taskPath(for: task),
                    iconName: ChecklistVisualSanitizer.sanitizedIcon(task.iconName),
                    colorHex: ChecklistVisualSanitizer.sanitizedColor(task.colorHex)
                )
            }
        )
    }

    func llmCategoryCandidates(
        maximumCount: Int = LLMSuggestionInputPolicy.maximumCandidateCount
    ) -> [LLMCategoryCandidate] {
        let candidateLimit = min(
            max(0, maximumCount),
            LLMSuggestionInputPolicy.maximumCandidateCount
        )
        guard candidateLimit > 0 else { return [] }
        let availableCategories = taskCategories
            .visibleDeduplicatedByID()
            .sorted { lhs, rhs in
                if lhs.sortOrder != rhs.sortOrder {
                    return lhs.sortOrder < rhs.sortOrder
                }
                let lhsKey = lhs.title.lowercased()
                let rhsKey = rhs.title.lowercased()
                if lhsKey != rhsKey { return lhsKey < rhsKey }
                if lhs.title != rhs.title { return lhs.title < rhs.title }
                return lhs.id.uuidString < rhs.id.uuidString
            }
            .prefix(candidateLimit)
            .map { category in
                LLMCategoryCandidate(
                    id: category.id,
                    title: category.title,
                    iconName: ChecklistVisualSanitizer.sanitizedIcon(
                        category.iconName ?? ChecklistVisualSanitizer.defaultIcon
                    ),
                    colorHex: ChecklistVisualSanitizer.sanitizedColor(
                        category.colorHex ?? ChecklistVisualSanitizer.defaultColor
                    )
                )
            }
        return LLMSuggestionInputPolicy.boundedCategoryCandidates(
            Array(availableCategories)
        )
    }

    func llmInboxSuggestionCandidates() -> LLMInboxSuggestionCandidates {
        let maximumCount = LLMSuggestionInputPolicy.maximumCandidateCount
        let balancedCount = maximumCount / 2
        let availableTaskCount = llmTaskCandidates(
            maximumCount: maximumCount
        ).count
        let availableCategoryCount = llmCategoryCandidates(
            maximumCount: maximumCount
        ).count
        var taskCount = min(availableTaskCount, balancedCount)
        var categoryCount = min(availableCategoryCount, balancedCount)
        var remainingCount = maximumCount - taskCount - categoryCount

        let additionalTaskCount = min(
            remainingCount,
            availableTaskCount - taskCount
        )
        taskCount += additionalTaskCount
        remainingCount -= additionalTaskCount
        categoryCount += min(
            remainingCount,
            availableCategoryCount - categoryCount
        )

        let categories = llmCategoryCandidates(maximumCount: categoryCount)
        let tasks = llmTaskCandidates(maximumCount: taskCount)
        return LLMSuggestionInputPolicy.boundedDestinationCandidates(
            tasks: tasks,
            categories: categories
        )
    }
}
