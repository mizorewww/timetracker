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
        case let .taskCategoryEditor(draft):
            TaskCategoryEditorSheet(store: store, initialDraft: draft)
        case let .manualTime(draft):
            ManualTimeSheet(store: store, initialDraft: draft)
        case let .segmentEditor(draft):
            SegmentEditorSheet(store: store, initialDraft: draft)
        case .startTaskPicker:
            TaskStartPickerSheet(
                store: store,
                onDone: {
                    router.dismiss(presentationID: presentation.id)
                },
                onCreateTask: {
                    router.replaceWithNewTask(
                        presentationID: presentation.id,
                        using: store
                    )
                }
            )
        case let .pomodoroTaskPicker(taskPicker):
            PomodoroFocusTaskPickerSheet(
                store: store,
                selectedTaskID: taskPicker.selectedTaskID,
                onSelect: { taskID in
                    taskPicker.selectTask(taskID)
                    router.dismiss(presentationID: presentation.id)
                },
                onCancel: {
                    router.dismiss(presentationID: presentation.id)
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
