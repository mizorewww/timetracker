import Foundation
import Observation

struct AppPresentation: Identifiable {
    enum Content {
        case taskEditor(
            draft: TaskEditorDraft,
            returnDestination: TimeTrackerStore.DesktopDestination
        )
        case recoveredTaskEditor(RecoveredTaskDraftPresentation)
        case taskCategoryEditor(TaskCategoryEditorDraft)
        case taskCategoryOrdering
        case manualTime(ManualTimeDraft)
        case segmentEditor(SegmentEditorDraft)
        case startTaskPicker
        case singleTaskPicker(SingleTaskPickerPresentation)
        case singleTaskCategoryPicker(SingleTaskCategoryPickerPresentation)
        case quickStartEditor(selectedIDs: [UUID])
        case settings
        case llmConfiguration(LLMConfigurationDraft)
        case llmPrompt(
            kind: LLMPromptKind,
            instructions: String,
            reasoningEffort: LLMReasoningEffort
        )
        case aiTaskPlanGenerator
    }

    let id: UUID
    let content: Content

    init(id: UUID = UUID(), content: Content) {
        self.id = id
        self.content = content
    }
}

struct SingleTaskPickerPresentation {
    let selectedTaskID: UUID?
    let context: TaskHierarchyPickerSelectionContext
    let selectTask: (UUID) -> Bool
}

struct SingleTaskCategoryPickerPresentation {
    let selectedCategoryID: UUID?
    let context: TaskCategoryPickerSelectionContext
    let selectCategory: (UUID) -> Bool
}

struct RecoveredTaskDraftPresentation {
    let sourceTaskID: UUID
    let proposedTaskID: UUID
    let savedTaskID: UUID?
    let draft: TaskEditorDraft
    let returnDestination: TimeTrackerStore.DesktopDestination
}

@MainActor
@Observable
final class AppPresentationRouter {
    var sheet: AppPresentation?

    var canPresent: Bool {
        sheet == nil
    }

    @discardableResult
    func present(_ content: AppPresentation.Content) -> Bool {
        guard canPresent else { return false }
        sheet = AppPresentation(content: content)
        return true
    }

    @discardableResult
    func replace(
        presentationID: UUID,
        with content: AppPresentation.Content
    ) -> Bool {
        guard sheet?.id == presentationID else { return false }
        sheet = AppPresentation(content: content)
        return true
    }

    func dismiss(presentationID: UUID) {
        guard sheet?.id == presentationID else { return }
        sheet = nil
    }
}

extension AppPresentationRouter {
    @discardableResult
    func presentNewTask(
        using store: TimeTrackerStore,
        parentID: UUID? = nil,
        preservingDestination: TimeTrackerStore.DesktopDestination? = nil,
        categoryID: UUID? = nil
    ) -> Bool {
        guard let content = newTaskContent(
            using: store,
            parentID: parentID,
            preservingDestination: preservingDestination,
            categoryID: categoryID
        ) else {
            return false
        }
        return present(content)
    }

    @discardableResult
    func replaceWithNewTask(
        presentationID: UUID,
        using store: TimeTrackerStore,
        preservingDestination: TimeTrackerStore.DesktopDestination? = nil
    ) -> Bool {
        guard let content = newTaskContent(
            using: store,
            parentID: nil,
            preservingDestination: preservingDestination,
            categoryID: nil
        ) else {
            return false
        }
        return replace(presentationID: presentationID, with: content)
    }

    @discardableResult
    func presentNewTaskCategory() -> Bool {
        present(.taskCategoryEditor(TaskCategoryEditorDraft()))
    }

    @discardableResult
    func presentEditTaskCategory(_ category: TaskCategory) -> Bool {
        present(.taskCategoryEditor(TaskCategoryEditorDraft(category: category)))
    }

    @discardableResult
    func presentTaskCategoryOrdering() -> Bool {
        present(.taskCategoryOrdering)
    }

    @discardableResult
    func presentManualTime(taskID: UUID? = nil, using store: TimeTrackerStore) -> Bool {
        let availableTasks = store.tasks.filter(store.isTaskAvailableForTracking)
        let requestedTask = taskID.flatMap { store.taskByID[$0] }
        let selectedTask = store.selectedTaskID.flatMap { store.taskByID[$0] }
        let target = requestedTask.flatMap { store.isTaskAvailableForTracking($0) ? $0.id : nil } ??
            selectedTask.flatMap { store.isTaskAvailableForTracking($0) ? $0.id : nil } ??
            availableTasks.first?.id
        return present(.manualTime(ManualTimeDraft(taskID: target, tasks: availableTasks)))
    }

    @discardableResult
    func presentEditSegment(_ segment: TimeSegment, using store: TimeTrackerStore) -> Bool {
        guard let draft = store.segmentEditorDraft(for: segment) else {
            store.errorMessage = SegmentMutationError.inconsistentSession.localizedDescription
            return false
        }
        return present(.segmentEditor(draft))
    }

    @discardableResult
    func presentStartTaskPicker() -> Bool {
        present(.startTaskPicker)
    }

    @discardableResult
    func presentPomodoroTaskPicker(
        selectedTaskID: UUID?,
        selectTask: @escaping (UUID) -> Void
    ) -> Bool {
        presentSingleTaskPicker(
            selectedTaskID: selectedTaskID,
            context: .pomodoro
        ) { taskID in
            selectTask(taskID)
            return true
        }
    }

    @discardableResult
    func presentSingleTaskPicker(
        selectedTaskID: UUID?,
        context: TaskHierarchyPickerSelectionContext,
        selectTask: @escaping (UUID) -> Bool
    ) -> Bool {
        present(.singleTaskPicker(SingleTaskPickerPresentation(
            selectedTaskID: selectedTaskID,
            context: context,
            selectTask: selectTask
        )))
    }

    @discardableResult
    func presentSingleTaskCategoryPicker(
        selectedCategoryID: UUID?,
        context: TaskCategoryPickerSelectionContext,
        selectCategory: @escaping (UUID) -> Bool
    ) -> Bool {
        present(.singleTaskCategoryPicker(
            SingleTaskCategoryPickerPresentation(
                selectedCategoryID: selectedCategoryID,
                context: context,
                selectCategory: selectCategory
            )
        ))
    }

    @discardableResult
    func presentQuickStartEditor(using store: TimeTrackerStore) -> Bool {
        present(.quickStartEditor(selectedIDs: store.preferences.quickStartTaskIDs))
    }

    @discardableResult
    func presentSettings() -> Bool {
        present(.settings)
    }

    @discardableResult
    func presentAITaskPlanGenerator() -> Bool {
        present(.aiTaskPlanGenerator)
    }

    @discardableResult
    func presentLLMConfiguration(using store: TimeTrackerStore) -> Bool {
        present(.llmConfiguration(LLMConfigurationDraft(
            endpoint: store.preferences.llmEndpoint,
            apiKey: store.preferences.llmAPIKey,
            selectedModel: store.preferences.llmSelectedModel,
            availableModels: store.preferences.llmAvailableModelIDs,
            reasoningEffort: store.preferences.llmReasoningEffort
        )))
    }

    @discardableResult
    func presentLLMPrompt(
        _ kind: LLMPromptKind,
        using store: TimeTrackerStore
    ) -> Bool {
        present(.llmPrompt(
            kind: kind,
            instructions: store.preferences.llmInstructions(for: kind),
            reasoningEffort: store.preferences.llmReasoningEffort
        ))
    }

    private func newTaskContent(
        using store: TimeTrackerStore,
        parentID: UUID?,
        preservingDestination: TimeTrackerStore.DesktopDestination?,
        categoryID: UUID?
    ) -> AppPresentation.Content? {
        if let parentID,
           store.parentEligibleTaskIDs.contains(parentID) == false
        {
            store.errorMessage = AppStrings.localized("task.parentUnavailable")
            return nil
        }
        return .taskEditor(
            draft: TaskEditorDraft(parentID: parentID, categoryID: categoryID),
            returnDestination: preservingDestination ?? store.desktopDestination
        )
    }
}
