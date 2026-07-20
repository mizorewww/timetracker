import SwiftUI

enum TaskEditorTextField: Hashable {
    case title
    case notes
}

struct TaskEditorForm: View {
    let store: TimeTrackerStore
    @Binding var draft: TaskEditorDraft
    let validation: TaskEditorValidation
    let parentCandidates: [TaskNode]
    let focusedTextField: FocusState<TaskEditorTextField?>.Binding
    let focusedChecklistDraftID: FocusState<UUID?>.Binding
    let orderedChecklistIndices: [Int]
    let toggleChecklistItem: (UUID) -> Void
    let moveChecklistItems: (IndexSet, Int) -> Void
    let addChecklistItem: (Int?) -> Void
    var showsTitleField = true
    var notesInteractionStyle: TaskNotesInteractionStyle = .editor

    var body: some View {
        Form {
            TaskEditorSections(
                store: store,
                draft: $draft,
                validation: validation,
                parentCandidates: parentCandidates,
                focusedTextField: focusedTextField,
                focusedChecklistDraftID: focusedChecklistDraftID,
                orderedChecklistIndices: orderedChecklistIndices,
                toggleChecklistItem: toggleChecklistItem,
                moveChecklistItems: moveChecklistItems,
                addChecklistItem: addChecklistItem,
                showsTitleField: showsTitleField,
                notesInteractionStyle: notesInteractionStyle
            )
        }
        .formStyle(.grouped)
        #if os(iOS)
        .scrollDismissesKeyboard(.interactively)
        #endif
        .accessibilityIdentifier("task.editor")
    }
}

struct TaskEditorSections: View {
    let store: TimeTrackerStore
    @Binding var draft: TaskEditorDraft
    let validation: TaskEditorValidation
    let parentCandidates: [TaskNode]
    let focusedTextField: FocusState<TaskEditorTextField?>.Binding
    let focusedChecklistDraftID: FocusState<UUID?>.Binding
    let orderedChecklistIndices: [Int]
    let toggleChecklistItem: (UUID) -> Void
    let moveChecklistItems: (IndexSet, Int) -> Void
    let addChecklistItem: (Int?) -> Void
    var showsTitleField = true
    var notesInteractionStyle: TaskNotesInteractionStyle = .editor

    var body: some View {
        Group {
            TaskInfoEditorSection(
                store: store,
                draft: $draft,
                validation: validation,
                parentCandidates: parentCandidates,
                showsTitleField: showsTitleField,
                focusedTextField: focusedTextField,
                dismissInputFocus: {
                    focusedTextField.wrappedValue = nil
                    focusedChecklistDraftID.wrappedValue = nil
                }
            )
            TaskPlanEditorSection(draft: $draft)
            TaskChecklistEditorSection(
                checklistItems: $draft.checklistItems,
                focusedChecklistDraftID: focusedChecklistDraftID,
                orderedChecklistIndices: orderedChecklistIndices,
                toggleChecklistItem: toggleChecklistItem,
                moveChecklistItems: moveChecklistItems,
                addChecklistItem: addChecklistItem
            )
            TaskNotesEditorSection(
                notes: $draft.notes,
                validationError: validation.notesError,
                interactionStyle: notesInteractionStyle,
                focusedTextField: focusedTextField
            )
        }
    }
}

struct TaskEditorValidation: Equatable {
    let titleError: TaskPersistenceValidationError?
    let notesError: TaskPersistenceValidationError?
    let iconNameError: TaskPersistenceValidationError?
    let colorHexError: TaskPersistenceValidationError?

    init(title: String, notes: String, iconName: String, colorHex: String) {
        let trimmedNotes = notes.trimmingCharacters(in: .whitespacesAndNewlines)
        let persistedNotes = trimmedNotes.isEmpty ? nil : trimmedNotes
        titleError = TaskPersistencePolicy.taskTitleValidationError(for: title)
        notesError = TaskPersistencePolicy.taskNotesValidationError(for: persistedNotes)
        iconNameError = TaskPersistencePolicy.taskIconNameValidationError(for: iconName)
        colorHexError = TaskPersistencePolicy.taskColorHexValidationError(for: colorHex)
    }

    var isValid: Bool {
        titleError == nil &&
            notesError == nil &&
            iconNameError == nil &&
            colorHexError == nil
    }
}

struct TaskEditorInlineValidationMessage: View {
    let error: TaskPersistenceValidationError
    let accessibilityIdentifier: String

    var body: some View {
        Label(error.localizedDescription, systemImage: "exclamationmark.circle.fill")
            .font(.footnote)
            .foregroundStyle(.red)
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(error.localizedDescription)
            .accessibilityAddTraits(.isStaticText)
            .accessibilityIdentifier(accessibilityIdentifier)
    }
}
