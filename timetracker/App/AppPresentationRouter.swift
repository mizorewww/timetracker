import Foundation
import Observation

struct AppPresentation: Identifiable {
    enum Content {
        case taskEditor(
            draft: TaskEditorDraft,
            returnDestination: TimeTrackerStore.DesktopDestination
        )
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

@MainActor
@Observable
final class AppPresentationRouter {
    var sheet: AppPresentation?
    /// The scene's feedback router; a presentation that cannot open because
    /// its target is stale reports why there.
    @ObservationIgnored let feedbackRouter: AppSceneFeedbackRouter
    #if os(macOS)
    /// Settings is a native window on macOS, not a sheet. Set by the root view
    /// from the `openSettings` environment action.
    @ObservationIgnored var openNativeSettings: (() -> Void)?
    #endif

    /// The open task detail's synchronous save of its pending edit, keyed by
    /// the detail instance so a disappearing detail cannot clear its
    /// replacement's registration.
    @ObservationIgnored private var openTaskDetailSave: (id: UUID, save: () -> Bool)?

    init(feedbackRouter: AppSceneFeedbackRouter) {
        self.feedbackRouter = feedbackRouter
    }

    var canPresent: Bool {
        sheet == nil
    }

    @discardableResult
    func present(_ content: AppPresentation.Content) -> Bool {
        #if os(macOS)
        if case .settings = content, let openNativeSettings {
            openNativeSettings()
            return true
        }
        #endif
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
    func registerOpenTaskDetailSave(id: UUID, save: @escaping () -> Bool) {
        openTaskDetailSave = (id, save)
    }

    func unregisterOpenTaskDetailSave(id: UUID) {
        guard openTaskDetailSave?.id == id else { return }
        openTaskDetailSave = nil
    }

    /// Archives a task after saving the open task detail's pending edit, so a
    /// debounced edit is not left behind on a task that stops accepting edits.
    /// An edit that cannot be saved stays in the detail and the archive is
    /// not performed.
    func archiveTask(_ taskID: UUID, using store: TimeTrackerStore) {
        if let openTaskDetailSave, openTaskDetailSave.save() == false {
            feedbackRouter.present(
                title: AppStrings.localized("task.autosave.failed"),
                message: AppStrings.localized("task.autosave.archiveBlocked")
            )
            return
        }
        feedbackRouter.perform { try store.archiveSelectedTask(taskID: taskID) }
    }

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
    func presentManualTime(taskID: UUID? = nil, using store: TimeTrackerStore) -> Bool {
        let availableTasks = store.trackableTasks
        let requestedTask = taskID.flatMap { store.taskByID[$0] }
        let selectedTask = store.selectedTaskID.flatMap { store.taskByID[$0] }
        let target = requestedTask.flatMap { store.isTaskAvailableForTracking($0) ? $0.id : nil } ??
            selectedTask.flatMap { store.isTaskAvailableForTracking($0) ? $0.id : nil } ??
            availableTasks.first?.id
        return present(.manualTime(ManualTimeDraft(taskID: target, tasks: availableTasks)))
    }

    @discardableResult
    func presentEditSegment(_ segment: TimeSegment, using store: TimeTrackerStore) -> Bool {
        presentEditSegment(.trackedSegment(segment.id), using: store)
    }

    @discardableResult
    func presentEditSegment(_ entryID: TimelineEntryID, using store: TimeTrackerStore) -> Bool {
        guard case .trackedSegment = entryID else {
            return false
        }
        guard let draft = store.segmentEditorDraft(for: entryID) else {
            feedbackRouter.present(SegmentMutationError.staleDraft)
            return false
        }
        return present(.segmentEditor(draft))
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

    func newTaskContent(
        using store: TimeTrackerStore,
        parentID: UUID? = nil,
        preservingDestination: TimeTrackerStore.DesktopDestination? = nil,
        categoryID: UUID? = nil
    ) -> AppPresentation.Content? {
        if let parentID,
           store.parentEligibleTaskIDs.contains(parentID) == false
        {
            feedbackRouter.present(
                title: AppStrings.localized("error.title"),
                message: AppStrings.localized("task.parentUnavailable")
            )
            return nil
        }
        return .taskEditor(
            draft: TaskEditorDraft(parentID: parentID, categoryID: categoryID),
            returnDestination: preservingDestination ?? store.desktopDestination
        )
    }
}
