import SwiftUI

private struct AppPresentationHostModifier: ViewModifier {
    let store: TimeTrackerStore
    let router: AppPresentationRouter
    let feedbackRouter: AppSceneFeedbackRouter

    func body(content: Content) -> some View {
        @Bindable var bindableRouter = router
        content.sheet(item: $bindableRouter.sheet) { presentation in
            AppPresentationSheet(
                store: store,
                router: router,
                feedbackRouter: feedbackRouter,
                presentation: presentation
            )
            .environment(router)
            .environment(feedbackRouter)
        }
    }
}

private struct AppPresentationSheet: View {
    let store: TimeTrackerStore
    let router: AppPresentationRouter
    let feedbackRouter: AppSceneFeedbackRouter
    let presentation: AppPresentation

    @ViewBuilder
    var body: some View {
        switch presentation.content {
        case let .taskEditor(draft, returnDestination):
            TaskEditorSheet(
                store: store,
                initialDraft: draft,
                returnDestination: returnDestination
            )
        case let .recoveredTaskEditor(recoveredDraft):
            RecoveredTaskEditorSheet(
                store: store,
                presentation: recoveredDraft
            )
        case let .taskCategoryEditor(draft):
            TaskCategoryEditorSheet(store: store, initialDraft: draft)
        case let .manualTime(draft):
            ManualTimeSheet(store: store, initialDraft: draft)
        case let .segmentEditor(draft):
            SegmentEditorSheet(store: store, initialDraft: draft)
        case .startTaskPicker:
            TaskHierarchyPickerSheet(
                store: store,
                mode: .timer,
                onDismiss: {
                    router.dismiss(presentationID: presentation.id)
                },
                onCreateTask: {
                    router.replaceWithNewTask(
                        presentationID: presentation.id,
                        using: store
                    )
                }
            )
        case let .singleTaskPicker(taskPicker):
            TaskHierarchyPickerSheet(
                store: store,
                mode: .singleSelection(
                    selectedTaskID: taskPicker.selectedTaskID,
                    context: taskPicker.context
                ),
                onDismiss: {
                    router.dismiss(presentationID: presentation.id)
                },
                onSelect: { taskID in
                    if taskPicker.selectTask(taskID) {
                        router.dismiss(presentationID: presentation.id)
                    }
                }
            )
        case let .quickStartEditor(selectedIDs):
            QuickStartEditorSheet(
                store: store,
                selectedIDs: selectedIDs,
                onSave: store.setQuickStartTaskIDs
            )
        case .settings:
            AppSettingsSheet(
                store: store,
                parentRouter: router,
                feedbackRouter: feedbackRouter,
                presentationID: presentation.id
            )
        case let .llmConfiguration(draft):
            LLMConfigurationEditor(
                endpoint: draft.endpoint,
                apiKey: draft.apiKey,
                selectedModel: draft.selectedModel,
                availableModels: draft.availableModels
            ) { configuration in
                store.setLLMConfiguration(
                    endpoint: configuration.endpoint,
                    apiKey: configuration.apiKey,
                    selectedModel: configuration.selectedModel,
                    availableModelIDs: configuration.availableModels
                )
            }
        case let .llmTaskPlanInstructions(instructions):
            LLMTaskPlanInstructionsEditor(instructions: instructions) {
                store.setLLMTaskPlanInstructions($0)
            }
        case .aiTaskPlanGenerator:
            AITaskPlanGeneratorSheet(
                store: store,
                onConfigureAI: {
                    router.replace(
                        presentationID: presentation.id,
                        with: .settings
                    )
                },
                onCreate: { draft in
                    switch store.saveAITaskPlan(draft) {
                    case let .saved(firstRootTaskID, _):
                        if let firstRootTaskID {
                            store.openTaskDetail(firstRootTaskID)
                        }
                        return .created
                    case let .failed(message):
                        return .failed(message: message)
                    }
                }
            )
        }
    }
}

private struct AppSettingsSheet: View {
    let store: TimeTrackerStore
    let parentRouter: AppPresentationRouter
    let feedbackRouter: AppSceneFeedbackRouter
    let presentationID: UUID
    @State private var childRouter = AppPresentationRouter()

    var body: some View {
        NavigationStack {
            SettingsView(store: store)
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button(AppStrings.done) {
                            parentRouter.dismiss(presentationID: presentationID)
                        }
                    }
                }
        }
        .environment(childRouter)
        .environment(feedbackRouter)
        .appPresentationHost(
            store: store,
            router: childRouter,
            feedbackRouter: feedbackRouter
        )
    }
}

extension View {
    func appPresentationHost(
        store: TimeTrackerStore,
        router: AppPresentationRouter,
        feedbackRouter: AppSceneFeedbackRouter
    ) -> some View {
        modifier(AppPresentationHostModifier(
            store: store,
            router: router,
            feedbackRouter: feedbackRouter
        ))
    }
}
