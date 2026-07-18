import Foundation

extension TaskHierarchyPicker {
    func displayedSections(
        in projection: TaskHierarchyProjection
    ) -> [TaskHierarchyProjection.Section] {
        projection.sections.filter { displayedItems(in: $0).isEmpty == false }
    }

    func displayedItems(
        in section: TaskHierarchyProjection.Section
    ) -> [TaskHierarchyProjection.Item] {
        switch mode {
        case .timer:
            section.items.filter { $0.isRunning == false }
        case .singleSelection:
            section.items
        }
    }

    func hasContent(
        projection: TaskHierarchyProjection,
        sections: [TaskHierarchyProjection.Section]
    ) -> Bool {
        if case .timer = mode, projection.runningItems.isEmpty == false {
            return true
        }
        return sections.isEmpty == false
    }

    func select(_ item: TaskHierarchyProjection.Item) {
        guard let task = store.task(for: item.id),
              store.isTaskAvailableForTracking(task) else {
            return
        }
        switch mode {
        case .timer:
            let outcome = store.performTimerPickerSelection(task)
            if outcome.shouldDismissPicker {
                onDismiss()
            }
        case .singleSelection:
            onSelect(item.id)
        }
    }

    func toggleExpansion(_ taskID: UUID) {
        if expandedTaskIDs.contains(taskID) {
            expandedTaskIDs.remove(taskID)
        } else {
            expandedTaskIDs.insert(taskID)
        }
    }

    func revealSelectedTask() {
        guard let selectedTaskID else { return }
        expandedTaskIDs.formUnion(store.ancestorTaskIDs(for: selectedTaskID))
    }

    func isSelected(_ item: TaskHierarchyProjection.Item) -> Bool {
        selectedTaskID == item.id
    }

    var selectedTaskID: UUID? {
        guard case .singleSelection(let selectedTaskID) = mode else {
            return nil
        }
        return selectedTaskID
    }

    func selectionIdentifier(
        for item: TaskHierarchyProjection.Item
    ) -> String {
        switch mode {
        case .timer:
            "timer.taskPicker.select.\(item.id.uuidString)"
        case .singleSelection:
            "pomodoro.taskPicker.select.\(item.id.uuidString)"
        }
    }

    func accessibilityLabel(
        for item: TaskHierarchyProjection.Item
    ) -> String {
        switch mode {
        case .timer:
            item.timerCommand.accessibilityLabel(for: item.identity.title)
        case .singleSelection:
            item.identity.title
        }
    }

    func accessibilityValue(
        for item: TaskHierarchyProjection.Item
    ) -> String {
        var values = [item.identity.fullPath]
        if item.isCompleted {
            values.append(TaskStatus.completed.displayName)
        } else if item.isAvailable == false {
            values.append(
                AppStrings.localized("task.status.blockedByCompletion")
            )
        }
        return values.joined(separator: ", ")
    }

    func accessibilityHint(
        for item: TaskHierarchyProjection.Item
    ) -> String {
        if let unavailableReason = item.unavailableReason {
            return unavailableReason
        }
        switch mode {
        case .timer:
            return item.timerCommand.accessibilityHint
        case .singleSelection:
            return ""
        }
    }
}
