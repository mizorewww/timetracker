import SwiftUI

private struct AppPresentationHostModifier: ViewModifier {
    let store: TimeTrackerStore
    let router: AppPresentationRouter

    func body(content: Content) -> some View {
        @Bindable var bindableRouter = router
        content.sheet(item: $bindableRouter.sheet) { presentation in
            AppPresentationSheet(
                store: store,
                router: router,
                presentation: presentation
            )
            .environment(router)
        }
    }
}

private struct AppPresentationSheet: View {
    let store: TimeTrackerStore
    let router: AppPresentationRouter
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
        case let .quickStartEditor(selectedIDs):
            QuickStartEditorSheet(
                store: store,
                selectedIDs: selectedIDs,
                onSave: store.setQuickStartTaskIDs
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

extension View {
    func appPresentationHost(
        store: TimeTrackerStore,
        router: AppPresentationRouter
    ) -> some View {
        modifier(AppPresentationHostModifier(store: store, router: router))
    }
}
