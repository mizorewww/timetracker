import SwiftUI

struct TaskInfoEditorSection: View {
    let store: TimeTrackerStore
    @Binding var draft: TaskEditorDraft
    let validation: TaskEditorValidation
    let colors: [String]
    let parentCandidates: [TaskNode]
    @FocusState private var isTitleFocused: Bool
    @State private var hasEditedTitle = false

    var body: some View {
        Section {
            VStack(alignment: .leading, spacing: 6) {
                TextField(AppStrings.localized("editor.task.name"), text: $draft.title)
                    .focused($isTitleFocused)
                    .accessibilityHint(visibleTitleError?.localizedDescription ?? "")
                if let visibleTitleError {
                    TaskEditorInlineValidationMessage(
                        error: visibleTitleError,
                        accessibilityIdentifier: "task.editor.title.error"
                    )
                }
            }
            TaskStatusPicker(
                selection: $draft.status,
                disabledStatuses: hasActiveTimerInSubtree && originalTask?.status != .completed
                    ? [.completed]
                    : []
            )
            parentPicker
                .disabled(isParentSelectionLocked)
            if draft.parentID == nil {
                categoryPicker
            }
            VStack(alignment: .leading, spacing: 6) {
                SymbolColorPickerRow(
                    colors: colors,
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
            VStack(alignment: .leading, spacing: 6) {
                inheritedCategoryHint
                if isParentSelectionLocked {
                    Label(
                        AppStrings.localized("task.parent.completedLocked"),
                        systemImage: "lock.fill"
                    )
                }
                if hasActiveTimerInSubtree, originalTask?.status != .completed {
                    Label(
                        AppStrings.localized("task.action.complete.stopFirst"),
                        systemImage: "stop.circle"
                    )
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .task {
            guard draft.taskID == nil else { return }
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

    private var categoryPicker: some View {
        Picker(AppStrings.localized("taskCategory.title"), selection: $draft.categoryID) {
            Text(.app("taskCategory.none")).tag(Optional<UUID>.none)
            ForEach(store.taskCategories, id: \.id) { category in
                Label(category.title, systemImage: category.iconName ?? "square.grid.2x2")
                    .tag(Optional(category.id))
            }
        }
    }

    @ViewBuilder
    private var inheritedCategoryHint: some View {
        if let category = inheritedCategory {
            Label {
                Text(String(format: AppStrings.localized("taskCategory.inherited"), category.title))
            } icon: {
                Image(systemName: category.iconName ?? "square.grid.2x2")
            }
            .font(.caption)
            .foregroundStyle(Color(hex: category.colorHex) ?? .secondary)
        }
    }

    private var inheritedCategory: TaskCategory? {
        guard let parentID = draft.parentID,
              let parent = store.task(for: parentID) else {
            return nil
        }
        return store.effectiveCategory(for: parent)
    }

    private var originalTask: TaskNode? {
        draft.taskID.flatMap { store.task(for: $0) }
    }

    private var isParentSelectionLocked: Bool {
        guard let originalTask else { return false }
        return !store.isTaskAvailableForTracking(originalTask)
    }

    private var hasActiveTimerInSubtree: Bool {
        guard let taskID = draft.taskID else { return false }
        return store.hasActiveTimer(inTaskSubtree: taskID)
    }

    private var parentPicker: some View {
        Picker(AppStrings.localized("editor.task.parent"), selection: $draft.parentID) {
            Text(.app("editor.task.rootLevel")).tag(Optional<UUID>.none)
            ForEach(parentCandidates, id: \.id) { task in
                Text(indentedTitle(task)).tag(Optional(task.id))
            }
        }
    }

    private func indentedTitle(_ task: TaskNode) -> String {
        String(repeating: "  ", count: task.depth) + task.title
    }
}
