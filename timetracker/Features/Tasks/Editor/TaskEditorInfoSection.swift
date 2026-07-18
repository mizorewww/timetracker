import SwiftUI

struct TaskInfoEditorSection: View {
    let store: TimeTrackerStore
    @Binding var draft: TaskEditorDraft
    let validation: TaskEditorValidation
    let parentCandidates: [TaskNode]
    @FocusState private var isTitleFocused: Bool
    @State private var hasEditedTitle = false
    @State private var hasRequestedInitialTitleFocus = false

    var body: some View {
        let originalTask = draft.taskID.flatMap { store.task(for: $0) }
        let parentChangeBlocker = originalTask.flatMap {
            store.parentChangeBlocker(for: $0)
        }
        let hasActiveTimerInSubtree = draft.taskID.map {
            store.hasActiveTimer(inTaskSubtree: $0)
        } ?? false
        let blocksCompletion = hasActiveTimerInSubtree && originalTask?.status != .completed

        Section {
            VStack(alignment: .leading, spacing: 6) {
                TextField(AppStrings.localized("editor.task.name"), text: $draft.title)
                    .focused($isTitleFocused)
                    .submitLabel(.done)
                    .onSubmit {
                        isTitleFocused = false
                    }
                    .accessibilityHint(visibleTitleError?.localizedDescription ?? "")
                    .accessibilityIdentifier("task.editor.title.field")
                if let visibleTitleError {
                    TaskEditorInlineValidationMessage(
                        error: visibleTitleError,
                        accessibilityIdentifier: "task.editor.title.error"
                    )
                }
            }
            TaskStatusPicker(
                selection: $draft.status,
                disabledStatuses: blocksCompletion ? [.completed] : []
            )
            TaskParentPickerRow(
                selection: $draft.parentID,
                options: parentOptions,
                changeBlocker: parentChangeBlocker
            )
            if draft.parentID == nil {
                TaskCategoryPickerRow(
                    selection: $draft.categoryID,
                    options: categoryOptions
                )
            }
            VStack(alignment: .leading, spacing: 6) {
                SymbolColorPickerRow(
                    pickerAccessibilityIdentifier: "symbol.picker.open.task",
                    onOpen: {
                        isTitleFocused = false
                    },
                    symbolName: $draft.iconName,
                    colorHex: $draft.colorHex
                )
                if let iconNameError = validation.iconNameError {
                    TaskEditorInlineValidationMessage(
                        error: iconNameError,
                        accessibilityIdentifier: "task.editor.symbol.error"
                    )
                }
                if let colorHexError = validation.colorHexError {
                    TaskEditorInlineValidationMessage(
                        error: colorHexError,
                        accessibilityIdentifier: "task.editor.color.error"
                    )
                }
            }
            .accessibilityElement(children: .contain)
            .accessibilityLabel(AppStrings.localized("editor.task.symbolColor"))
        } header: {
            Text(AppStrings.localized("editor.task.info"))
        } footer: {
            TaskHierarchyEditorHints(
                inheritedCategory: inheritedCategoryHint,
                parentChangeBlocker: parentChangeBlocker,
                blocksCompletion: blocksCompletion
            )
        }
        .task {
            guard draft.taskID == nil,
                  hasRequestedInitialTitleFocus == false else { return }
            hasRequestedInitialTitleFocus = true
            isTitleFocused = true
        }
        .onChange(of: draft.title) {
            hasEditedTitle = true
        }
    }

    private var visibleTitleError: TaskPersistenceValidationError? {
        guard let error = validation.titleError else { return nil }
        if case .required = error,
           draft.taskID == nil,
           hasEditedTitle == false {
            return nil
        }
        return error
    }

    private var inheritedCategoryHint: TaskInheritedCategoryHint? {
        guard let parentID = draft.parentID,
              let parent = store.task(for: parentID),
              let category = store.effectiveCategory(for: parent) else {
            return nil
        }
        return TaskInheritedCategoryHint(
            title: category.title,
            iconName: category.iconName ?? "square.grid.2x2",
            colorHex: category.colorHex
        )
    }

    private var categoryOptions: [TaskCategoryPickerOption] {
        store.taskCategories.map {
            TaskCategoryPickerOption(
                id: $0.id,
                title: $0.title,
                iconName: $0.iconName ?? "square.grid.2x2"
            )
        }
    }

    private var parentOptions: [TaskParentPickerOption] {
        parentCandidates.map { task in
            TaskParentPickerOption(
                id: task.id,
                title: store.taskIdentityPresentation(for: task).fullPath,
                isAvailable: store.isTaskAvailableForTracking(task)
            )
        }
    }
}
