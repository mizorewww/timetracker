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
        let modeItems = switch mode {
        case .timer:
            section.items.filter { $0.isRunning == false }
        case .singleSelection, .multipleSelection:
            section.items
        }
        return modeItems.filter {
            $0.isAvailable || selectedTaskIDs.contains($0.id)
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
        guard let task = store.task(for: item.id) else { return }
        switch mode {
        case .timer:
            guard store.isTaskAvailableForTracking(task) else { return }
            let outcome = store.performTimerPickerSelection(task)
            if outcome.shouldDismissPicker {
                onDismiss()
            }
        case .singleSelection:
            guard store.isTaskAvailableForTracking(task) else { return }
            onSelect(item.id)
        case .multipleSelection:
            guard isSelectionDisabled(for: item) == false else { return }
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

    func revealSelectedTasks(_ taskIDs: Set<UUID>) {
        for selectedTaskID in taskIDs {
            expandedTaskIDs.formUnion(store.ancestorTaskIDs(for: selectedTaskID))
        }
    }

    func isSelected(_ item: TaskHierarchyProjection.Item) -> Bool {
        selectedTaskIDs.contains(item.id)
    }

    var selectedTaskIDs: Set<UUID> {
        switch mode {
        case .timer:
            []
        case let .singleSelection(selectedTaskID, _):
            selectedTaskID.map { [$0] } ?? []
        case let .multipleSelection(selectedTaskIDs, _, _):
            selectedTaskIDs
        }
    }

    func isSelectionLimitReached(
        for item: TaskHierarchyProjection.Item
    ) -> Bool {
        guard case let .multipleSelection(
            selectedTaskIDs,
            _,
            maximumSelectionCount
        ) = mode,
        let maximumSelectionCount else {
            return false
        }
        return selectedTaskIDs.count >= maximumSelectionCount &&
            selectedTaskIDs.contains(item.id) == false
    }

    func isSelectionDisabled(
        for item: TaskHierarchyProjection.Item
    ) -> Bool {
        if item.isAvailable == false {
            guard case .multipleSelection = mode, isSelected(item) else {
                return true
            }
        }
        return isSelectionLimitReached(for: item)
    }

    func selectionIdentifier(
        for item: TaskHierarchyProjection.Item
    ) -> String {
        switch mode {
        case .timer:
            "timer.taskPicker.select.\(item.id.uuidString)"
        case let .singleSelection(_, context):
            "\(context.accessibilityIdentifier).select.\(item.id.uuidString)"
        case let .multipleSelection(_, context, _):
            "\(context.accessibilityIdentifier).select.\(item.id.uuidString)"
        }
    }

    func accessibilityLabel(
        for item: TaskHierarchyProjection.Item
    ) -> String {
        switch mode {
        case .timer:
            item.timerCommand.accessibilityLabel(for: item.identity.title)
        case .singleSelection, .multipleSelection:
            item.identity.title
        }
    }

    func accessibilityValue(
        for item: TaskHierarchyProjection.Item
    ) -> String {
        var components = [item.identity.fullPath]
        if case .timer = mode {
            // Timer rows expose their action instead of repeating passive state.
        } else if item.isRunning {
            components.append(AppStrings.running)
        }
        if case .multipleSelection = mode {
            components.append(
                AppStrings.localized(
                    isSelected(item)
                        ? "taskPicker.selection.selected"
                        : "taskPicker.selection.notSelected"
                )
            )
        }
        components.append(
            String(
                format: AppStrings.localized("tasks.workedFormat"),
                DurationFormatter.compact(item.workedSeconds)
            )
        )
        if let progress = item.checklistProgress {
            components.append(
                String(
                    format: AppStrings.localized("checklist.progressFormat"),
                    progress.completedCount,
                    progress.totalCount
                )
            )
        }
        return ListFormatter.localizedString(byJoining: components)
    }

    func accessibilityHint(
        for item: TaskHierarchyProjection.Item
    ) -> String {
        if let unavailableReason = item.unavailableReason,
           isSelectionDisabled(for: item) {
            return unavailableReason
        }
        if isSelectionLimitReached(for: item),
           case let .multipleSelection(_, _, maximumSelectionCount) = mode,
           let maximumSelectionCount {
            return String(
                format: AppStrings.localized(
                    "taskPicker.selection.limitReachedFormat"
                ),
                maximumSelectionCount
            )
        }
        switch mode {
        case .timer:
            return item.timerCommand.accessibilityHint
        case let .singleSelection(_, context):
            return context.selectionHint
        case let .multipleSelection(_, context, _):
            return context.selectionHint
        }
    }
}
