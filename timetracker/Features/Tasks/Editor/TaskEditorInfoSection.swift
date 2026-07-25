import SwiftUI

struct TaskInfoEditorSection: View {
    let store: TimeTrackerStore
    @Binding var draft: TaskEditorDraft
    let validation: TaskEditorValidation
    let parentCandidates: [TaskNode]
    var showsTitleField = true
    let focusedTextField: FocusState<TaskEditorTextField?>.Binding
    let dismissInputFocus: () -> Void
    @State private var hasEditedTitle = false
    @State private var hasRequestedInitialTitleFocus = false

    var body: some View {
        let originalTask = draft.taskID.flatMap { store.task(for: $0) }
        let parentChangeBlocker = originalTask.flatMap {
            store.parentChangeBlocker(for: $0)
        }

        Section {
            if showsTitleField {
                VStack(alignment: .leading, spacing: 6) {
                    TextField(AppStrings.localized("editor.task.name"), text: $draft.title)
                        .focused(focusedTextField, equals: .title)
                        .submitLabel(.done)
                        .onSubmit {
                            focusedTextField.wrappedValue = nil
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
            }
            if let appleHealthCategory {
                TaskReadOnlyCategoryRow(
                    category: appleHealthCategory
                )
            } else {
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
            }
            VStack(alignment: .leading, spacing: 6) {
                SymbolColorPickerRow(
                    pickerAccessibilityIdentifier: "symbol.picker.open.task",
                    onOpen: dismissInputFocus,
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
            if inheritedCategoryHint != nil || parentChangeBlocker != nil {
                TaskHierarchyEditorHints(
                    inheritedCategory: inheritedCategoryHint,
                    parentChangeBlocker: parentChangeBlocker
                )
            }
        }
        .task {
            guard showsTitleField,
                  draft.taskID == nil,
                  hasRequestedInitialTitleFocus == false else { return }
            hasRequestedInitialTitleFocus = true
            focusedTextField.wrappedValue = .title
        }
        .onChange(of: draft.title) {
            hasEditedTitle = true
        }
    }

    private var visibleTitleError: TaskPersistenceValidationError? {
        guard let error = validation.titleError else { return nil }
        if case .required = error,
           draft.taskID == nil,
           hasEditedTitle == false
        {
            return nil
        }
        return error
    }

    private var inheritedCategoryHint: TaskInheritedCategoryHint? {
        guard let parentID = draft.parentID,
              let parent = store.task(for: parentID),
              let category = store.effectiveCategory(for: parent)
        else {
            return nil
        }
        return TaskInheritedCategoryHint(
            title: category.title,
            iconName: category.iconName ?? "square.grid.2x2",
            colorHex: category.colorHex
        )
    }

    private var appleHealthCategory: TaskInheritedCategoryHint? {
        guard let taskID = draft.taskID,
              let taskDefinition = AppleHealthTaskCatalog.taskDefinition(
                  for: taskID
              )
        else {
            return nil
        }
        if let category = store.taskCategories.first(where: {
            $0.id == taskDefinition.categoryID
        }) {
            return TaskInheritedCategoryHint(
                title: category.title,
                iconName: category.iconName ?? "square.grid.2x2",
                colorHex: category.colorHex
            )
        }
        let categoryDefinition = AppleHealthTaskCatalog.categoryDefinition(
            for: taskDefinition.role.categoryRole
        )
        return TaskInheritedCategoryHint(
            title: AppStrings.localized(
                categoryDefinition.titleLocalizationKey
            ),
            iconName: categoryDefinition.iconName,
            colorHex: categoryDefinition.colorHex
        )
    }

    private var categoryOptions: [TaskCategoryPickerOption] {
        store.taskCategories.map {
            TaskCategoryPickerOption(
                id: $0.id,
                title: $0.title,
                iconName: $0.iconName ?? "square.grid.2x2",
                colorHex: $0.colorHex
            )
        }
    }

    private var parentOptions: [TaskParentPickerOption] {
        parentCandidates.map { task in
            TaskParentPickerOption(
                id: task.id,
                title: store.taskIdentityPresentation(for: task).fullPath,
                isAvailable: store.isTaskEligibleAsParent(task)
            )
        }
    }
}
